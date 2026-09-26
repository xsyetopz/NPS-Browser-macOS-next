import AppKit
import NPSBrowserAppResources
import Testing
@testable import NPSBrowserApp

@Suite(.sourceEnglish)
@MainActor
struct NavigationCellBuilderTests {
  @Test
  func headingCellShowsTheLocalizedTitleAsAccessibleStaticText() {
    // Arrange
    let title = AppResources.localized("section.bookmarks")

    // Act
    let cell = NavigationCellBuilder.headingCell(titleKey: "section.bookmarks")

    // Assert
    #expect(cell.stringValue == title)
    #expect(cell.textColor == .secondaryLabelColor)
    #expect(cell.lineBreakMode == .byTruncatingTail)
    #expect(cell.isAccessibilityElement())
    #expect(cell.accessibilityRole() == .staticText)
    #expect(cell.accessibilityLabel() == title)
  }

  @Test
  func sectionCellUsesTheNavigationTitleAndTheFullTitleForAccessibility() throws {
    // Arrange
    let section = BrowserSection.psVita
    let fullTitle = AppResources.localized(section.titleKey)

    // Act
    let cell = NavigationCellBuilder.sectionCell(for: section)

    // Assert
    let label = try #require(cell.textField)
    let image = try #require(cell.imageView)
    #expect(section.navigationTitleKey != section.titleKey)
    #expect(label.stringValue == AppResources.localized(section.navigationTitleKey))
    #expect(label.lineBreakMode == .byTruncatingTail)
    #expect(image.image != nil)
    #expect(image.image?.accessibilityDescription == fullTitle)
    #expect(cell.subviews.contains(label))
    #expect(cell.subviews.contains(image))
    #expect(cell.isAccessibilityElement())
    #expect(cell.accessibilityLabel() == fullTitle)
  }
}
