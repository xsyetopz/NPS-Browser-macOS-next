import Foundation
import Testing
@testable import NPSCore

extension CatalogParserTests {
  @Test
  func safeFilenameRemovesTraversalAndCSVQuotesCells() {
    let item = CatalogItem(
      titleID: "ID-1",
      name: "../folder\\game:name.pkg",
      consoleType: .PS3,
      fileType: .Game
    )
    let bookmark = Bookmark(
      id: item.id,
      titleID: item.titleID,
      downloadURL: nil,
      name: "folder, \"disc\"",
      fileType: "Game",
      consoleType: "PS3",
      zrif: nil
    )

    #expect(!item.safeFilename().contains("/"))
    #expect(!item.safeFilename().contains("\\"))
    #expect(item.safeFilename() == "folder-game-name.pkg.pkg")
    #expect(Bookmark.csv([bookmark]).contains("\"folder, \"\"disc\"\"\""))
  }

  @Test
  func blankIdentifiersUseAStableDistinctFallback() {
    let first = CatalogItem(
      titleID: "",
      region: "US",
      name: "",
      packageURL: URL(string: "https://cdn.example/first.pkg"),
      consoleType: .PS3,
      fileType: .Game
    )
    let second = CatalogItem(
      titleID: "",
      region: "US",
      name: "",
      packageURL: URL(string: "https://cdn.example/second.pkg"),
      consoleType: .PS3,
      fileType: .Game
    )

    #expect(first.id != first.legacyPrimaryKey)
    #expect(first.id != second.id)
    #expect(first.safeFilename() == "first.pkg")
  }
}
