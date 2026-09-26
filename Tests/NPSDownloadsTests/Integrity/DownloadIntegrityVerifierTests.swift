import Foundation
import Testing
@testable import NPSDownloads

extension DownloadCoordinatorTests {
  @Test("rejects server errors, HTML/XML documents, mismatched lengths and hashes")
  func invalidResponsesFailClosed() async throws {
    let pkg = makePKGFixture(repetitions: 4)
    let server = try FixtureHTTPServer { request in
      switch request.path {
      case "/status": return FixtureHTTPResponse(status: 503, body: Data("offline".utf8))
      case "/html":
        var response = FixtureHTTPResponse(body: Data("<!doctype html><html>not found</html>".utf8))
        response.contentType = "text/html"
        return response
      case "/xml":
        var response = FixtureHTTPResponse(body: Data("<?xml version=\"1.0\"?><error/>".utf8))
        response.contentType = "application/xml"
        return response
      case "/header":
        return FixtureHTTPResponse(
          body: Data([0x7f, 0x50, 0x4b, 0x47] + Array(repeating: 0, count: 300))
        )
      case "/length": return FixtureHTTPResponse(body: pkg)
      default: return FixtureHTTPResponse(body: pkg)
      }
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = try makeCoordinator(
      destination: directory,
      persistence: directory.appendingPathComponent("jobs.plist")
    )
    let cases: [(String, Int64?, String?)] = [
      ("status", nil, nil), ("html", nil, nil), ("xml", nil, nil), ("header", nil, nil),
      ("length", Int64(pkg.count + 7), nil),
      ("hash", Int64(pkg.count), String(repeating: "0", count: 64)),
    ]
    var ids: [UUID] = []
    for (path, expectedLength, expectedHash) in cases {
      let job = try await coordinator.enqueue(
        DownloadJobRequest(
          sourceURL: server.baseURL.appendingPathComponent(path),
          title: path,
          consoleType: "PSV",
          expectedByteCount: expectedLength,
          sha256: expectedHash
        )
      )
      ids.append(job.id)
    }
    let results = try await waitForAllTerminal(coordinator, ids: ids)
    #expect(results.allSatisfy { $0.state == .failed })
    #expect(
      results.allSatisfy {
        $0.destinationURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true
      }
    )
    #expect(results.contains { $0.errorMessage?.contains("HTTP status 503") == true })
    #expect(
      results.contains {
        $0.errorMessage?.contains("text/html") == true
          || $0.errorMessage?.contains("HTML or XML") == true
      }
    )
    #expect(results.contains { $0.errorMessage?.contains("application/xml") == true })
    #expect(results.contains { $0.errorMessage?.contains("minimum header structure") == true })
    #expect(results.contains { $0.errorMessage?.contains("size") == true })
    #expect(results.contains { $0.errorMessage?.contains("SHA-256") == true })
  }

  @Test("accepts only 16-byte RAP payloads and never installs failed RAP responses")
  func validatesRAPPayloadsBeforeInstallation() async throws {
    let validRAP = Data((0..<16).map(UInt8.init))
    let tooShortRAP = Data((0..<15).map(UInt8.init))
    let xmlError = Data("<error>x</error>".utf8)
    #expect(xmlError.count == 16)
    let server = try FixtureHTTPServer { request in
      switch request.path {
      case "/valid": return FixtureHTTPResponse(body: validRAP)
      case "/short": return FixtureHTTPResponse(body: tooShortRAP)
      case "/xml-error":
        var response = FixtureHTTPResponse(body: xmlError)
        response.contentType = "application/octet-stream"
        return response
      case "/markup":
        var response = FixtureHTTPResponse(body: Data("<html>RAP unavailable</html>".utf8))
        response.contentType = "application/octet-stream"
        return response
      case "/status": return FixtureHTTPResponse(status: 503, body: validRAP)
      default: return FixtureHTTPResponse(status: 404, body: Data())
      }
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = try makeCoordinator(
      destination: directory,
      persistence: directory.appendingPathComponent("jobs.plist")
    )
    var ids: [String: UUID] = [:]
    for path in ["valid", "short", "xml-error", "markup", "status"] {
      let job = try await coordinator.enqueue(
        DownloadJobRequest(
          sourceURL: server.baseURL.appendingPathComponent(path),
          title: "RAP \(path)",
          consoleType: "PS3",
          titleID: "NPUB12345",
          fileExtension: "rap"
        )
      )
      ids[path] = job.id
    }

    let results = try await waitForAllTerminal(coordinator, ids: Array(ids.values))
    let resultByID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
    let resultByPath = Dictionary(
      uniqueKeysWithValues: ids.compactMap { path, id in resultByID[id].map { (path, $0) } }
    )

    let validResult = try #require(resultByPath["valid"])
    #expect(validResult.state == .complete)
    let validDestination = try #require(validResult.destinationURL)
    #expect(try Data(contentsOf: validDestination) == validRAP)
    for path in ["short", "xml-error", "markup", "status"] {
      let failed = try #require(resultByPath[path])
      #expect(failed.state == .failed)
      #expect(
        failed.destinationURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true
      )
    }
    #expect(resultByPath["short"]?.errorMessage?.contains("16-byte RAP") == true)
    #expect(resultByPath["xml-error"]?.errorMessage?.contains("HTML or XML") == true)
    #expect(resultByPath["markup"]?.errorMessage?.contains("HTML or XML") == true)
    #expect(resultByPath["status"]?.errorMessage?.contains("HTTP status 503") == true)
  }
}
