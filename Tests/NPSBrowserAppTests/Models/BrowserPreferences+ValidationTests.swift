import Foundation
import NPSBrowserAppResources
import NPSCore
import Testing
@testable import NPSBrowserApp

@Suite(.sourceEnglish)
struct BrowserPreferencesValidationTests {
  @Test
  func formRejectsInvalidCatalogueURLWithPerSourceMessage() {
    // Arrange
    let preferences = makePreferences()

    // Act
    let result = preferences.applyingCatalogueURL(
      "ftp://example.test/PS3_GAMES.tsv",
      for: .ps3Games
    )

    // Assert
    let expected = BrowserPreferences.ValidationFailure.invalidCatalogueURL(
      .ps3Games,
      "ftp://example.test/PS3_GAMES.tsv"
    )
    #expect(failure(of: result) == expected)
    #expect(
      expected.formMessage == "\(AppResources.localized("preferences.invalidCatalogueURL"))\n"
        + AppResources.localized("source.ps3Games")
    )
  }

  @Test
  func formRejectsUnparseableCatalogueURLText() {
    // Arrange
    let preferences = makePreferences()

    // Act
    let result = preferences.applyingCatalogueURL("not a url", for: .psvGames)

    // Assert
    #expect(failure(of: result) == .invalidCatalogueURL(.psvGames, "not a url"))
  }

  @Test
  func relativeDownloadFolderIsRejectedWithFolderMessage() throws {
    // Arrange
    var preferences = makePreferences()
    preferences.downloadDirectory = try #require(URL(string: "relative/Downloads"))

    // Act
    let failure = preferences.validationFailure

    // Assert
    #expect(failure == .invalidDownloadDirectory(preferences.downloadDirectory))
    #expect(failure?.formMessage == AppResources.localized("preferences.invalidDownloadFolder"))
  }

  @Test
  func validFormValuesApplyAndKeepUnpackPS3Packages() throws {
    // Arrange
    var preferences = makePreferences()
    preferences.extraction.unpackPS3Packages = true
    var values = makeFormValues()
    values.downloadDirectoryPath = "/tmp/NPS Downloads"
    values.concurrentDownloads = 7
    values.compressionFactor = 5

    // Act
    let updated = try preferences.applying(values).get().applyingCatalogueURL(
      "file:///tmp/PSV_GAMES.tsv",
      for: .psvGames
    ).get()

    // Assert
    #expect(updated.catalogueURLs[.psvGames] == URL(string: "file:///tmp/PSV_GAMES.tsv"))
    #expect(
      updated.downloadDirectory == URL(fileURLWithPath: "/tmp/NPS Downloads", isDirectory: true)
    )
    #expect(updated.concurrentDownloads == 7)
    #expect(updated.extraction.compressionFactor == 5)
    #expect(updated.extraction.unpackPS3Packages)
    #expect(updated.validationFailure == nil)
  }

  @Test
  func validCatalogueURLChangesOnlyThatSource() throws {
    // Arrange
    let preferences = makePreferences()

    // Act
    let updated = try preferences.applyingCatalogueURL(
      "https://mirror.example/PS3_GAMES.tsv",
      for: .ps3Games
    ).get()

    // Assert
    #expect(updated.catalogueURLs[.ps3Games] == URL(string: "https://mirror.example/PS3_GAMES.tsv"))
    #expect(updated.catalogueURLs[.psvGames] == preferences.catalogueURLs[.psvGames])
    #expect(updated.downloadDirectory == preferences.downloadDirectory)
  }

  @Test
  func formValuesLeaveCatalogueURLsUnchanged() throws {
    // Arrange
    var preferences = makePreferences()
    preferences.catalogueURLs[.psvGames] = URL(string: "https://mirror.example/PSV_GAMES.tsv")

    // Act
    let updated = try preferences.applying(makeFormValues()).get()

    // Assert
    #expect(updated.catalogueURLs == preferences.catalogueURLs)
  }

  @Test
  func saveValidationRejectsZeroConcurrency() {
    // Arrange
    var preferences = makePreferences()
    preferences.concurrentDownloads = 0

    // Act
    let failure = preferences.validationFailure

    // Assert
    #expect(failure == .invalidConcurrency(0))
  }

  @Test
  func catalogueURLRuleAcceptsWebAndLocalFilesOnly() throws {
    // Arrange
    let accepted = ["https://example.test/a.tsv", "http://example.test/a.tsv", "file:///tmp/a.tsv"]
    let rejected = [
      "ftp://example.test/a.tsv", "https://user:pw@example.test/a.tsv", "file://remote/tmp/a.tsv",
    ]

    // Act
    let acceptedResults = try accepted.map {
      BrowserPreferences.isSupportedCatalogueURL(try #require(URL(string: $0)))
    }
    let rejectedResults = try rejected.map {
      BrowserPreferences.isSupportedCatalogueURL(try #require(URL(string: $0)))
    }

    // Assert
    #expect(acceptedResults.allSatisfy { $0 })
    #expect(rejectedResults.allSatisfy { !$0 })
  }
}

private func makePreferences() -> BrowserPreferences {
  BrowserPreferences(
    catalogueURLs: Dictionary(
      uniqueKeysWithValues: CatalogSource.allCases.map { ($0, $0.defaultURL) }
    ),
    downloadDirectory: URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true),
    concurrentDownloads: 3,
    extraction: ExtractionSettings(),
    hideInvalidURLItems: true
  )
}

private func makeFormValues() -> PreferencesFormValues {
  PreferencesFormValues(
    downloadDirectoryPath: "/tmp/Downloads",
    hideInvalidURLItems: true,
    concurrentDownloads: 3,
    extractAfterDownload: true,
    keepPackage: false,
    saveAsZip: false,
    createLicense: true,
    compressPSPISO: false,
    compressionFactor: 1
  )
}

private func failure(
  of result: Result<BrowserPreferences, BrowserPreferences.ValidationFailure>
) -> BrowserPreferences.ValidationFailure? {
  if case let .failure(failure) = result { return failure }
  return nil
}
