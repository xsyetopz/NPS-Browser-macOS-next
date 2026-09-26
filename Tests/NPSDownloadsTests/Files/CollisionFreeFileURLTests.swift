import Foundation
import Testing
@testable import NPSDownloads

@Suite(.sourceEnglish)
struct CollisionFreeFileURLTests {
  @Test
  func skipsOccupiedAndExistingPathsWithNumberedSuffixes() throws {
    // Arrange
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "CollisionFreeFileURLTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data().write(to: directory.appendingPathComponent("Game_ Name.pkg"))
    let occupied: Set<String> = [directory.appendingPathComponent("Game_ Name (2).pkg").path]

    // Act
    let url = CollisionFreeFileURL.next(
      title: "Game: Name",
      fileExtension: "PKG",
      lowercasingExtension: true,
      in: directory,
      occupiedPaths: occupied
    )

    // Assert
    #expect(url == directory.appendingPathComponent("Game_ Name (3).pkg", isDirectory: false))
  }

  @Test
  func keepsTheExtensionCaseWhenNotLowercasing() {
    // Arrange
    let directory = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)", isDirectory: true)

    // Act
    let url = CollisionFreeFileURL.next(
      title: "../Title",
      fileExtension: "PKG",
      lowercasingExtension: false,
      in: directory,
      occupiedPaths: []
    )

    // Assert
    #expect(url.lastPathComponent == "_Title.PKG")
  }
}
