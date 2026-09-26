import Foundation
import Testing
@testable import NPSDownloads

@Suite(.sourceEnglish)
struct CompatibilityPackTests {
  @Test("validates archives with many entries without scanning all prior names per file")
  func manyArchiveEntriesValidate() throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let entries = (0..<12_000).map { index in
      StoredZipEntry(name: "files/\(index).bin", data: Data([UInt8(index & 0xFF)]))
    }
    let archive = workspace.appendingPathComponent("many-entries.ppk")
    try storedZip(entries).write(to: archive)
    try CompatibilityPackArchive.validate(archive)
  }

  @Test("unsafe ZIP names and Unix symlink entries are rejected")
  func unsafeZipEntriesAreRejected() throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let invalidEntries = [
      StoredZipEntry(name: "../outside.txt", data: Data("escape".utf8)),
      StoredZipEntry(name: "/absolute.txt", data: Data("escape".utf8)),
      StoredZipEntry(name: "folder\\outside.txt", data: Data("escape".utf8)),
      StoredZipEntry(name: "link", data: Data("../../outside.txt".utf8), mode: 0xA1FF),
    ]
    for (index, entry) in invalidEntries.enumerated() {
      let archive = workspace.appendingPathComponent("unsafe-\(index).ppk")
      try storedZip([entry]).write(to: archive)
      do {
        try CompatibilityPackArchive.validate(archive)
        Issue.record("unsafe archive entry \(entry.name) was accepted")
      } catch {
        #expect(
          error.localizedDescription.contains("unsafe")
            || error.localizedDescription.contains("symbolic links")
        )
      }
    }
  }

  @Test("valid ZIP comments may contain an end-record signature")
  func endRecordSignatureInsideComment() throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let comment = Data(
      [0x50, 0x4B, 0x05, 0x06] + Array(repeating: 0x11, count: 16) + [0xFF, 0xFF]
    )
    let archive = workspace.appendingPathComponent("comment-signature.ppk")
    try storedZip([StoredZipEntry(name: "file.txt", data: Data("valid".utf8))], comment: comment)
      .write(to: archive)
    try CompatibilityPackArchive.validate(archive)
  }
}
