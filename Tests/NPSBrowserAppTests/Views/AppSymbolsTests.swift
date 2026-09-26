import AppKit
import NPSBrowserAppResources
import Testing
@testable import NPSBrowserApp

@Suite(.serialized, .sourceEnglish)
@MainActor
struct AppSymbolsTests {
  @Test
  func toolbarActionsHaveDrawnFallbackImagesForCatalina() throws {
    for (symbol, description) in [
      ("star", "Add Bookmark"), ("star.fill", "Remove Bookmark"), ("arrow.down.circle", "Download"),
      ("list.bullet.rectangle", "Downloads"),
    ] {
      let image = try #require(AppSymbols.fallbackImage(named: symbol, description: description))
      #expect(image.isTemplate)
      #expect(image.accessibilityDescription == description)
      #expect(image.size == NSSize(width: 18, height: 18))
    }
    #expect(AppSymbols.fallbackImage(named: "unsupported", description: "Unsupported") == nil)
  }
}

@MainActor
@Test(.sourceEnglish)
func everySidebarSectionHasAnAccessibleCatalinaFallbackIcon() throws {
  for section in BrowserSection.allCases {
    let description = AppResources.localized(section.titleKey)
    let image = try #require(
      AppSymbols.fallbackImage(named: section.symbolName, description: description)
    )
    #expect(image.isTemplate)
    #expect(image.accessibilityDescription == description)
  }
}

@Test(.sourceEnglish)
func legacyRAPButtonFallbackKeepsItsAccessibilityDescription() throws {
  let label = "Download RAP"
  let image = try #require(AppSymbols.fallbackImage(named: "key.horizontal", description: label))

  #expect(image.isTemplate)
  #expect(image.accessibilityDescription == label)
  #expect(image.size == NSSize(width: 18, height: 18))
}
