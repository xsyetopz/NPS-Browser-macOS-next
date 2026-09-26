import Foundation
@testable import NPSDownloads

final class CompatibilityRequestLog: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [String] = []

  func append(_ path: String) {
    lock.lock()
    defer { lock.unlock() }
    stored.append(path)
  }

  var paths: [String] {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }
}

enum CompatibilityPackTestFailure: Error { case timeout(UUID) }

extension CompatibilityPackTests {
  func waitForTerminal(
    _ coordinator: DownloadCoordinator,
    id: UUID
  ) async throws -> DownloadSnapshot {
    for _ in 0..<500 {
      if let job = await coordinator.snapshots().first(where: { $0.id == id }),
        job.state == .complete || job.state == .failed
      {
        return job
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    throw CompatibilityPackTestFailure.timeout(id)
  }
}

func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "NPSCompatibilityPackTests-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

func createZipArchive(at archiveURL: URL, files: [String: String]) throws -> Data {
  let inputDirectory = archiveURL.deletingLastPathComponent().appendingPathComponent(
    "input-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: inputDirectory) }
  for (path, value) in files {
    let file = inputDirectory.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(value.utf8).write(to: file)
  }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
  process.arguments = ["-q", "-r", archiveURL.path] + files.keys.sorted()
  process.currentDirectoryURL = inputDirectory
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe
  try process.run()
  process.waitUntilExit()
  let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  guard process.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: output])
  }
  return try Data(contentsOf: archiveURL)
}
