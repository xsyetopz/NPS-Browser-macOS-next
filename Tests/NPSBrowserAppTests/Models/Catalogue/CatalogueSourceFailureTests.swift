import Foundation
import NPSCore
import Testing
@testable import NPSBrowserApp

@Suite(.sourceEnglish)
struct CatalogueSourceFailureTests {
  @Test
  func partialFailureListsLocalizedSourceTitlesNotKeys() {
    // Arrange
    let error = CatalogueRefreshError.partialFailure([
      CatalogueSourceFailure(source: .psvGames, reason: .text("HTTP 503")),
      CatalogueSourceFailure(
        source: .compatPacks,
        reason: LocalizedMessage(CatalogParseError.missingHeader)
      ),
    ])
    let chinese = Localization(preferredLanguages: ["zh-CN"])

    // Act
    let english = error.localizedDescription
    let translated = Localization.$override.withValue(chinese) { error.localizedDescription }

    // Assert
    #expect(english.contains("\nPS Vita Games: HTTP 503"))
    #expect(english.contains("\nCompatibility Packs: The catalog does not contain a header row."))
    #expect(!english.contains("src_"))
    #expect(translated.contains("\(chinese.string("source.psvGames"))：HTTP 503"))
  }
}
