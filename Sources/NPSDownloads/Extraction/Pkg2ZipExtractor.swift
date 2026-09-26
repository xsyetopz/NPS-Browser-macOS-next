import Foundation
import NPSCore

public struct Pkg2ZipExtractor: PackageExtractor {
  public let executableURL: URL

  public init(executableURL: URL) { self.executableURL = executableURL }

  public func extract(
    packageURL: URL,
    request: DownloadJobRequest,
    destinationDirectory: URL
  ) async throws -> URL {
    if request.consoleType.caseInsensitiveCompare("PS3") == .orderedSame {
      throw PackageExtractionError.unsupportedConsole("PS3")
    }
    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
      throw PackageExtractionError.missingHelper(executableURL)
    }

    let identity =
      request.titleID?.isEmpty == false
      ? request.titleID! : "\(request.consoleType)-\(request.sourceURL.lastPathComponent)"
    let directoryName = safeComponent("\(request.fileNameTitle) [\(identity)]")
    let outputDirectory = uniqueDirectory(named: directoryName, in: destinationDirectory)
    do {
      try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      throw PackageExtractionError.launchFailed(
        LocalizedMessage("error.extraction.folderCreationFailed", .message(LocalizedMessage(error)))
      )
    }

    var arguments: [String] = []
    if !request.extractionOptions.saveAsZip { arguments.append("-x") }
    if request.consoleType.caseInsensitiveCompare("PSP") == .orderedSame,
      request.extractionOptions.compressPSPISO
    {
      arguments.append("-c\(request.extractionOptions.compressionFactor)")
    }
    arguments.append(packageURL.path)
    if request.extractionOptions.createLicense, let zrif = request.zrif, !zrif.isEmpty,
      zrif != "MISSING"
    {
      arguments.append(zrif)
    }
    let (status, output) = try await ProcessRunner.run(
      executableURL: executableURL,
      arguments: arguments,
      currentDirectoryURL: outputDirectory
    )
    guard status == 0 else {
      throw PackageExtractionError.failed(exitCode: status, output: .text(output))
    }
    let contents = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)
    guard !contents.isEmpty else {
      throw PackageExtractionError.failed(
        exitCode: status,
        output: LocalizedMessage("error.extraction.emptyOutput")
      )
    }
    return outputDirectory
  }

  private func uniqueDirectory(named name: String, in parent: URL) -> URL {
    let fileManager = FileManager.default
    var attempt = 1
    while true {
      let marker = attempt == 1 ? "" : " (\(attempt))"
      let candidate = parent.appendingPathComponent("\(name)\(marker)", isDirectory: true)
      if !fileManager.fileExists(atPath: candidate.path) { return candidate }
      attempt += 1
    }
  }

  private func safeComponent(_ raw: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_()."))
    let value = String(
      raw.precomposedStringWithCanonicalMapping.unicodeScalars.map {
        allowed.contains($0) ? Character($0) : "_"
      }
    ).trimmingCharacters(
      in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
    )
    return String((value.isEmpty ? "Package" : value).prefix(150))
  }
}

private enum ProcessRunner {
  static func run(
    executableURL: URL,
    arguments: [String],
    currentDirectoryURL: URL
  ) async throws -> (Int32, String) {
    do {
      return try await BlockingWork.run {
        try runSynchronously(
          executableURL: executableURL,
          arguments: arguments,
          currentDirectoryURL: currentDirectoryURL
        )
      }
    } catch { throw PackageExtractionError.launchFailure(wrapping: error) }
  }

  private static func runSynchronously(
    executableURL: URL,
    arguments: [String],
    currentDirectoryURL: URL
  ) throws -> (Int32, String) {
    let fileManager = FileManager.default
    let logURL = fileManager.temporaryDirectory.appendingPathComponent(
      "pkg2zip-\(UUID().uuidString).log"
    )
    guard fileManager.createFile(atPath: logURL.path, contents: nil) else {
      throw PackageExtractionError.launchFailed(
        LocalizedMessage("error.extraction.logCreationFailed")
      )
    }
    defer { try? fileManager.removeItem(at: logURL) }

    let outputHandle = try FileHandle(forWritingTo: logURL)
    defer { try? outputHandle.close() }
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectoryURL
    process.standardOutput = outputHandle
    process.standardError = outputHandle
    try process.run()
    process.waitUntilExit()
    try? outputHandle.synchronize()

    let outputData = (try? Data(contentsOf: logURL)) ?? Data()
    let output = String(data: outputData, encoding: .utf8) ?? ""
    return (process.terminationStatus, String(output.suffix(2_000)))
  }
}
