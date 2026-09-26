import Foundation

final class DownloadStore: @unchecked Sendable {
  private let fileURL: URL
  private let lock = NSLock()

  init(fileURL: URL) { self.fileURL = fileURL }

  func load() throws -> [PersistedDownload] {
    lock.lock()
    defer { lock.unlock() }
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    return try PropertyListDecoder().decode([PersistedDownload].self, from: data)
  }

  func save(_ downloads: [PersistedDownload]) throws {
    lock.lock()
    defer { lock.unlock() }
    let parent = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(downloads)
    try data.write(to: fileURL, options: .atomic)
  }
}
