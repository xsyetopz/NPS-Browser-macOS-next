import Foundation
import NPSCore
import NPSDownloads
import NPSPersistence
import Testing
@testable import NPSBrowserApp

@Test(.sourceEnglish)
func applicationSettingsSaveAndReloadLocalCatalogueFileURL() async throws {
  let suiteName = "NPSBrowserAppTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "NPSBrowserAppTests-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let settings = SettingsStore(defaults: defaults)
  let catalogue = try RealmCatalogueStore(
    fileURL: directory.appendingPathComponent("catalogue.realm")
  )
  let downloads = try DownloadCoordinator(
    preferences: { DownloadPreferences(downloadDirectory: directory, concurrentDownloads: 2) },
    persistenceURL: directory.appendingPathComponent("downloads.plist")
  )
  let app = ApplicationDataSource(settings: settings, catalogue: catalogue, downloads: downloads)
  let fileURL = try #require(Bundle.module.url(forResource: "LocalCatalogue", withExtension: "tsv"))
  var preferences = try app.loadPreferences()
  preferences.catalogueURLs[.psvGames] = fileURL

  try app.savePreferences(preferences)
  let reloaded = try app.loadPreferences()
  let text = try await CatalogueTextLoader.fetchText(
    from: try #require(reloaded.catalogueURLs[.psvGames])
  )
  let items = try CatalogParser.parseTSV(text, kind: CatalogKind(console: .PSV, fileType: .Game))

  #expect(reloaded.catalogueURLs[.psvGames] == fileURL)
  #expect(items.map(\.titleID) == ["PCSA00007"])
}

@Test(.sourceEnglish)
func savingPreferencesRejectsRelativeDownloadFolderAndUnsupportedCatalogueURL() throws {
  // Arrange
  let suiteName = "NPSBrowserAppTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "NPSBrowserAppTests-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let app = ApplicationDataSource(
    settings: SettingsStore(defaults: defaults),
    catalogue: try RealmCatalogueStore(
      fileURL: directory.appendingPathComponent("catalogue.realm")
    ),
    downloads: try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: directory, concurrentDownloads: 2) },
      persistenceURL: directory.appendingPathComponent("downloads.plist")
    )
  )
  let relativeFolder = try #require(URL(string: "relative/Downloads"))
  let ftpURL = try #require(URL(string: "ftp://example.test/PSV_GAMES.tsv"))
  var relative = try app.loadPreferences()
  relative.downloadDirectory = relativeFolder
  var unsupported = try app.loadPreferences()
  unsupported.catalogueURLs[.psvGames] = ftpURL

  // Act / Assert
  #expect(throws: SettingsError.invalidDownloadDirectory(relativeFolder)) {
    try app.savePreferences(relative)
  }
  #expect(throws: SettingsError.invalidCatalogueURL(.psvGames, ftpURL.absoluteString)) {
    try app.savePreferences(unsupported)
  }
  #expect(try app.loadPreferences().catalogueURLs[.psvGames] == CatalogSource.psvGames.defaultURL)
}
