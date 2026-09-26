import Foundation
import NPSCore

extension CompatibilityPackArchive {
  static func extract(
    packURL: URL,
    patchURL: URL?,
    titleID: String,
    into consoleDirectory: URL
  ) throws -> URL {
    try assembleOutput(
      packURL: packURL,
      patchURL: patchURL,
      titleID: titleID,
      into: consoleDirectory,
      overlayExistingOutput: false
    )
  }

  static func applyPatch(_ patchURL: URL, titleID: String, into consoleDirectory: URL) throws -> URL
  {
    try assembleOutput(
      packURL: nil,
      patchURL: patchURL,
      titleID: titleID,
      into: consoleDirectory,
      overlayExistingOutput: true
    )
  }

  private static func assembleOutput(
    packURL: URL?,
    patchURL: URL?,
    titleID: String,
    into consoleDirectory: URL,
    overlayExistingOutput: Bool
  ) throws -> URL {
    if let packURL { try validate(packURL) }
    if let patchURL { try validate(patchURL) }
    guard packURL != nil || patchURL != nil else { throw invalid("error.archive.reason.noArchive") }
    try requireDirectory(consoleDirectory, create: false)
    let repatch = consoleDirectory.appendingPathComponent("rePatch", isDirectory: true)
    try requireDirectory(repatch, create: true)
    let id = safeLeaf(titleID)
    let output = repatch.appendingPathComponent(id, isDirectory: true)
    let staging = repatch.appendingPathComponent(
      ".\(id).stage-\(UUID().uuidString)",
      isDirectory: true
    )
    let backup = repatch.appendingPathComponent(
      ".\(id).backup-\(UUID().uuidString)",
      isDirectory: true
    )
    let fileManager = FileManager.default
    defer { try? fileManager.removeItem(at: staging) }
    if overlayExistingOutput,
      (try? fileManager.destinationOfSymbolicLink(atPath: output.path)) != nil
    {
      throw unsafe(output.path, "error.archive.reason.outputIsSymbolicLink")
    }
    if overlayExistingOutput, fileManager.fileExists(atPath: output.path) {
      try requireDirectory(output, create: false)
      do { try fileManager.copyItem(at: output, to: staging) } catch {
        try? fileManager.removeItem(at: staging)
        throw CompatibilityPackArchiveError.extraction(
          LocalizedMessage(
            "error.archive.reason.outputCopyFailed",
            .message(LocalizedMessage(error))
          )
        )
      }
      // Never pass an untrusted existing tree to unzip until the copied
      // tree has been checked for symlinks and path escapes.
      try inspectTree(staging)
    } else {
      try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
    }
    if let packURL {
      try unzip(["-tqq", packURL.path], in: staging)
      try unzip(["-o", "-qq", packURL.path, "-d", staging.path], in: staging)
      try inspectTree(staging)
    }
    if let patchURL {
      try unzip(["-tqq", patchURL.path], in: staging)
      try unzip(["-o", "-qq", patchURL.path, "-d", staging.path], in: staging)
      try inspectTree(staging)
    }
    var backedUp = false
    do {
      if fileManager.fileExists(atPath: output.path) {
        try requireDirectory(output, create: false)
        try fileManager.moveItem(at: output, to: backup)
        backedUp = true
      }
      try fileManager.moveItem(at: staging, to: output)
    } catch {
      if backedUp { try? fileManager.moveItem(at: backup, to: output) }
      throw CompatibilityPackArchiveError.destination(LocalizedMessage(error))
    }
    if backedUp { try? fileManager.removeItem(at: backup) }
    return output
  }

  private static func requireDirectory(_ url: URL, create: Bool) throws {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
      let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
      guard isDirectory.boolValue, attrs[.type] as? FileAttributeType == .typeDirectory else {
        throw CompatibilityPackArchiveError.destination(
          LocalizedMessage("error.archive.reason.notDirectory", .text(url.path))
        )
      }
      return
    }
    guard create else {
      throw CompatibilityPackArchiveError.destination(
        LocalizedMessage("error.archive.reason.unavailable", .text(url.path))
      )
    }
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    } catch { throw CompatibilityPackArchiveError.destination(LocalizedMessage(error)) }
  }

  private static func inspectTree(_ root: URL) throws {
    let rootPath = root.standardizedFileURL.path
    guard
      let e = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
        options: []
      )
    else {
      throw CompatibilityPackArchiveError.extraction(
        LocalizedMessage("error.archive.reason.stagingUnreadable")
      )
    }
    for case let url as URL in e {
      guard url.standardizedFileURL.path.hasPrefix(rootPath + "/") else {
        throw unsafe(url.path, "error.archive.reason.escapedStaging")
      }
      let v = try url.resourceValues(forKeys: [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
      ])
      guard v.isSymbolicLink != true, v.isDirectory == true || v.isRegularFile == true else {
        throw unsafe(url.path, "error.archive.reason.specialFile")
      }
    }
  }

  private static func unzip(_ args: [String], in directory: URL) throws {
    let binary = URL(fileURLWithPath: "/usr/bin/unzip")
    guard FileManager.default.isExecutableFile(atPath: binary.path) else {
      throw CompatibilityPackArchiveError.extraction(
        LocalizedMessage("error.archive.reason.unavailable", .text(binary.path))
      )
    }
    let p = Process()
    let pipe = Pipe()
    let output = BoundedProcessOutput()
    let drain = ProcessPipeDrain(pipe: pipe, output: output)
    let drainQueue = DispatchQueue(label: "com.npsbrowser.ppk-unzip-output")
    p.executableURL = binary
    p.arguments = args
    p.currentDirectoryURL = directory
    p.standardOutput = pipe
    p.standardError = pipe
    drainQueue.async { drain.run() }
    do {
      try p.run()
      try? pipe.fileHandleForWriting.close()
      p.waitUntilExit()
      drainQueue.sync {}
    } catch {
      try? pipe.fileHandleForWriting.close()
      drainQueue.sync {}
      throw CompatibilityPackArchiveError.extraction(LocalizedMessage(error))
    }
    let outputText = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard p.terminationStatus == 0 else {
      throw CompatibilityPackArchiveError.extraction(
        outputText.isEmpty
          ? LocalizedMessage("error.archive.reason.unzipStatus", .integer(Int(p.terminationStatus)))
          : .text(outputText)
      )
    }
  }

  private static func safeLeaf(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_()."))
    let mapped = String(
      value.precomposedStringWithCanonicalMapping.unicodeScalars.map {
        allowed.contains($0) ? Character($0) : "_"
      }
    )
    let leaf = mapped.trimmingCharacters(
      in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
    )
    return leaf.isEmpty || leaf == "." || leaf == ".." ? "Unknown" : String(leaf.prefix(120))
  }
}

private final class BoundedProcessOutput: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()
  private let maximumBytes = 64 * 1024

  func append(_ chunk: Data) {
    lock.lock()
    defer { lock.unlock() }
    let remaining = maximumBytes - data.count
    if remaining > 0 { data.append(chunk.prefix(remaining)) }
  }

  var text: String {
    lock.lock()
    defer { lock.unlock() }
    // Lossy decoding is intended: diagnostic output must survive invalid UTF-8.
    // swiftlint:disable:next optional_data_string_conversion
    return String(decoding: data, as: UTF8.self)
  }
}

private final class ProcessPipeDrain: @unchecked Sendable {
  private let pipe: Pipe
  private let output: BoundedProcessOutput

  init(pipe: Pipe, output: BoundedProcessOutput) {
    self.pipe = pipe
    self.output = output
  }

  func run() {
    while true {
      let chunk = pipe.fileHandleForReading.readData(ofLength: 8 * 1024)
      guard !chunk.isEmpty else { return }
      output.append(chunk)
    }
  }
}
