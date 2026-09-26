import Foundation
import Testing
@testable import NPSDownloads

extension CompatibilityPackTests {
  @Test("standalone CPatch preserves files in the existing title output")
  func patchOnlyOverlayKeepsBaseFilesAndAppliesPatch() throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    let existingOutput = library.appendingPathComponent("PSV/rePatch/PCSE00640", isDirectory: true)
    try FileManager.default.createDirectory(at: existingOutput, withIntermediateDirectories: true)
    try Data("base game data".utf8).write(to: existingOutput.appendingPathComponent("base.dat"))
    try Data("old config".utf8).write(to: existingOutput.appendingPathComponent("config.txt"))
    let patchURL = workspace.appendingPathComponent("patch.ppk")
    try storedZip([
      StoredZipEntry(name: "patch.dat", data: Data("patch data".utf8)),
      StoredZipEntry(name: "config.txt", data: Data("patched config".utf8)),
    ]).write(to: patchURL)

    let output = try CompatibilityPackArchive.applyPatch(
      patchURL,
      titleID: "PCSE00640",
      into: library.appendingPathComponent("PSV", isDirectory: true)
    )

    #expect(output == existingOutput)
    #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("base.dat").path))
    #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("patch.dat").path))
    if FileManager.default.fileExists(atPath: output.appendingPathComponent("base.dat").path) {
      #expect(
        try Data(contentsOf: output.appendingPathComponent("base.dat"))
          == Data("base game data".utf8)
      )
    }
    #expect(
      try Data(contentsOf: output.appendingPathComponent("config.txt"))
        == Data("patched config".utf8)
    )
  }

  @Test("standalone CPatch rejects unsafe prior symlinks without changing the output")
  func patchOnlyOverlayRejectsExistingSymlinkTree() throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    let existingOutput = library.appendingPathComponent("PSV/rePatch/PCSE00640", isDirectory: true)
    try FileManager.default.createDirectory(at: existingOutput, withIntermediateDirectories: true)
    let sentinel = workspace.appendingPathComponent("outside.txt")
    let originalSentinel = Data("outside stays unchanged".utf8)
    try originalSentinel.write(to: sentinel)
    try FileManager.default.createSymbolicLink(
      at: existingOutput.appendingPathComponent("escape-link"),
      withDestinationURL: sentinel
    )
    let patchURL = workspace.appendingPathComponent("patch.ppk")
    try storedZip([StoredZipEntry(name: "patch.dat", data: Data("must not be applied".utf8))])
      .write(to: patchURL)

    do {
      _ = try CompatibilityPackArchive.applyPatch(
        patchURL,
        titleID: "PCSE00640",
        into: library.appendingPathComponent("PSV", isDirectory: true)
      )
      Issue.record("An unsafe existing symlink tree should not be overlaid.")
    } catch {
      #expect(
        error.localizedDescription.contains("symbolic links")
          || error.localizedDescription.contains("unsafe")
      )
    }

    #expect(try Data(contentsOf: sentinel) == originalSentinel)
    #expect(
      try FileManager.default.destinationOfSymbolicLink(
        atPath: existingOutput.appendingPathComponent("escape-link").path
      ) == sentinel.path
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: existingOutput.appendingPathComponent("patch.dat").path
      )
    )
  }
}
