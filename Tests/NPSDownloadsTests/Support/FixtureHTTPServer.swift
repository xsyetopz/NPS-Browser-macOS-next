import Darwin
import Foundation

struct FixtureHTTPRequest: Sendable {
  let path: String
  let headers: [String: String]
}

struct FixtureHTTPResponse: Sendable {
  let status: Int
  let body: Data
  var contentType = "application/octet-stream"
  var headers: [String: String] = [:]
  var advertisedLength: Int?
  var chunkSize = 64 * 1024
  var chunkDelayMicroseconds: useconds_t = 0
  var interruptAfterBytes: Int?

  init(status: Int = 200, body: Data) {
    self.status = status
    self.body = body
  }
}

/// A loopback-only fixture server. Requests use real URLSession download tasks,
/// including redirects and server disconnects, rather than a mocked downloader.
final class FixtureHTTPServer: @unchecked Sendable {
  private let socketDescriptor: Int32
  private let workQueue = DispatchQueue(label: "nps-download-fixture-accept", qos: .utility)
  private let requestHandler: @Sendable (FixtureHTTPRequest) -> FixtureHTTPResponse
  private let lock = NSLock()
  private var stopped = false
  private var currentConnections = 0
  private var highestConnections = 0
  private var currentResponses = 0
  private var highestResponses = 0
  let port: UInt16

  var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }
  var maximumObservedConnections: Int {
    lock.lock()
    defer { lock.unlock() }
    return highestResponses
  }

  init(handler: @escaping @Sendable (FixtureHTTPRequest) -> FixtureHTTPResponse) throws {
    requestHandler = handler
    let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    socketDescriptor = socketFD
    guard socketFD >= 0 else { throw POSIXError(.EIO) }
    var reuse: Int32 = 1
    _ = setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let bindResult = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }
    guard Darwin.listen(socketFD, 16) == 0 else { throw POSIXError(.EIO) }

    var boundAddress = sockaddr_in()
    var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(socketFD, $0, &addressLength)
      }
    }
    guard nameResult == 0 else { throw POSIXError(.EIO) }
    port = UInt16(bigEndian: boundAddress.sin_port)
    workQueue.async { [weak self] in self?.acceptRequests() }
  }

  deinit {
    lock.lock()
    stopped = true
    lock.unlock()
    Darwin.shutdown(socketDescriptor, SHUT_RDWR)
    Darwin.close(socketDescriptor)
  }

  private func acceptRequests() {
    while true {
      lock.lock()
      let shouldStop = stopped
      lock.unlock()
      if shouldStop { return }
      let client = Darwin.accept(socketDescriptor, nil, nil)
      if client < 0 {
        lock.lock()
        let didStop = stopped
        lock.unlock()
        if didStop { return }
        continue
      }
      lock.lock()
      currentConnections += 1
      highestConnections = max(highestConnections, currentConnections)
      lock.unlock()
      DispatchQueue.global(qos: .utility).async { [weak self] in self?.serve(client) }
    }
  }

  private func serve(_ client: Int32) {
    var requestFinished = false
    var responseTracked = false
    defer {
      Darwin.shutdown(client, SHUT_RDWR)
      Darwin.close(client)
      if !requestFinished {
        lock.lock()
        currentConnections -= 1
        lock.unlock()
      }
      if responseTracked {
        lock.lock()
        currentResponses -= 1
        lock.unlock()
      }
    }
    var noSignal: Int32 = 1
    _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    guard let request = readRequest(client) else { return }
    lock.lock()
    currentResponses += 1
    highestResponses = max(highestResponses, currentResponses)
    responseTracked = true
    lock.unlock()
    let response = requestHandler(request)

    var headers = response.headers
    headers["Content-Length"] = String(response.advertisedLength ?? response.body.count)
    headers["Content-Type"] = response.contentType
    headers["Connection"] = "close"
    let statusText: String
    switch response.status {
    case 200: statusText = "OK"
    case 206: statusText = "Partial Content"
    case 302: statusText = "Found"
    case 404: statusText = "Not Found"
    case 503: statusText = "Service Unavailable"
    default: statusText = "Fixture"
    }
    var headerText = "HTTP/1.1 \(response.status) \(statusText)\r\n"
    for (key, value) in headers { headerText += "\(key): \(value)\r\n" }
    headerText += "\r\n"
    let end = min(response.body.count, response.interruptAfterBytes ?? response.body.count)
    guard writeAll(Data(headerText.utf8), to: client) else { return }

    var offset = 0
    while offset < end {
      let chunkEnd = min(end, offset + max(1, response.chunkSize))
      guard writeAll(response.body.subdata(in: offset..<chunkEnd), to: client) else { return }
      offset = chunkEnd
      if offset < end && response.chunkDelayMicroseconds > 0 {
        usleep(response.chunkDelayMicroseconds)
      }
    }
    // Count active response bodies, not the few instructions needed to close
    // a socket after all bytes have already been delivered.
    lock.lock()
    currentConnections -= 1
    lock.unlock()
    requestFinished = true
    lock.lock()
    currentResponses -= 1
    lock.unlock()
    responseTracked = false
  }

  private func readRequest(_ socket: Int32) -> FixtureHTTPRequest? {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4 * 1024)
    while !data.contains(Data([13, 10, 13, 10])), data.count < 64 * 1024 {
      let count = recv(socket, &buffer, buffer.count, 0)
      guard count > 0 else { return nil }
      data.append(contentsOf: buffer.prefix(count))
    }
    guard let text = String(data: data, encoding: .utf8),
      let firstLine = text.components(separatedBy: "\r\n").first
    else { return nil }
    let parts = firstLine.split(separator: " ")
    guard parts.count >= 2 else { return nil }
    var headers: [String: String] = [:]
    for line in text.components(separatedBy: "\r\n").dropFirst() {
      guard let separator = line.firstIndex(of: ":") else { continue }
      headers[String(line[..<separator]).lowercased()] = String(
        line[line.index(after: separator)...]
      ).trimmingCharacters(in: .whitespaces)
    }
    return FixtureHTTPRequest(path: String(parts[1]), headers: headers)
  }

  private func writeAll(_ data: Data, to socket: Int32) -> Bool {
    data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return true }
      var sent = 0
      while sent < bytes.count {
        let count = Darwin.send(socket, baseAddress.advanced(by: sent), bytes.count - sent, 0)
        if count <= 0 { return false }
        sent += count
      }
      return true
    }
  }
}
