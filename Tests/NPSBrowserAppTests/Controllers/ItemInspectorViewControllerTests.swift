import AppKit
import NPSBrowserAppResources
import Testing
@testable import NPSBrowserApp

@Suite(.serialized, .sourceEnglish)
@MainActor
struct ItemInspectorViewControllerTests {
  @Test
  func inspectorLabelsEachDetailAndHidesEmptyRows() {
    // Arrange
    let inspector = ItemInspectorViewController()
    _ = inspector.view
    let entry = layoutEntry(id: "layout-inspector", title: "Inspector Game")

    // Act
    inspector.show(entry: entry, bookmarked: false)

    // Assert
    #expect(inspector.detailValue(forKey: "inspector.titleID") == "PCSA00001")
    #expect(inspector.detailValue(forKey: "inspector.console") == "PS Vita")
    #expect(inspector.detailValue(forKey: "inspector.type") == "Game")
    #expect(inspector.detailValue(forKey: "inspector.region") == "US")
    #expect(inspector.detailValue(forKey: "inspector.size") == nil)
    #expect(inspector.detailValue(forKey: "inspector.contentID") == nil)
  }
}

@MainActor
@Test(.sourceEnglish)
func bookmarkedInspectorButtonUsesTheFilledStarAndCurrentAccessibleAction() throws {
  let inspector = ItemInspectorViewController()
  _ = inspector.view
  let entry = BrowserEntry(
    id: "bookmark-ax-test",
    title: "Bookmark Accessibility Test",
    titleID: "NPUG10004",
    console: "PlayStation Mobile",
    consoleCode: "PSM",
    category: "Game",
    region: "US",
    fileSize: nil,
    packageURL: URL(string: "https://example.test/bookmark-ax.pkg"),
    sha256: nil,
    contentID: nil
  )
  inspector.show(entry: entry, bookmarked: false)
  let bookmarkButton = try #require(
    descendants(of: inspector.view).compactMap { $0 as? NSButton }.first {
      $0.title == AppResources.localized("action.bookmark.add")
    }
  )

  #expect(
    bookmarkButton.image?.accessibilityDescription == AppResources.localized("action.bookmark.add")
  )
  #expect(bookmarkButton.accessibilityLabel() == AppResources.localized("action.bookmark.add"))

  inspector.show(entry: entry, bookmarked: true)

  #expect(bookmarkButton.title == AppResources.localized("action.bookmark.remove"))
  #expect(
    bookmarkButton.image?.accessibilityDescription
      == AppResources.localized("action.bookmark.remove")
  )
  #expect(bookmarkButton.accessibilityLabel() == AppResources.localized("action.bookmark.remove"))
}
