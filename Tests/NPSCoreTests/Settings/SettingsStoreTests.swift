import Foundation
import Testing
@testable import NPSCore

@Suite(.sourceEnglish)
struct SettingsStoreTests {
  @Test
  func readsExistingKeysAndValidatesURLAndDownloadValues() throws {
    let suiteName = "NPSCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SettingsStore(defaults: defaults)
    let customSource = try #require(URL(string: "https://catalog.example/games.tsv"))
    let customFolder = URL(fileURLWithPath: "/Volumes/NPS Library", isDirectory: true)
    let libraryFolder = URL(fileURLWithPath: "/Volumes/NPS Library/Extracted", isDirectory: true)

    try store.setCatalogueURL(customSource, for: .ps3Games)
    try store.setDownloadDirectory(customFolder)
    try store.setDownloadLibraryDirectory(libraryFolder)
    try store.setConcurrentDownloads(5)
    store.updateExtractionSettings(
      ExtractionSettings(keepPackage: true, compressPSPISO: true, compressionFactor: 7)
    )

    let snapshot = store.snapshot()
    #expect(snapshot.catalogueURLs[.ps3Games] == customSource)
    #expect(snapshot.downloadDirectory == customFolder.standardizedFileURL)
    #expect(snapshot.downloadLibraryDirectory == libraryFolder.standardizedFileURL)
    #expect(snapshot.concurrentDownloads == 5)
    #expect(snapshot.extraction.keepPackage)
    #expect(snapshot.extraction.compressPSPISO)
    #expect(snapshot.extraction.compressionFactor == 7)
    #expect(store.catalogueURL(for: .psvGames) == CatalogSource.psvGames.defaultURL)
    #expect(defaults.object(forKey: "dl_library_location") != nil)
    #expect(defaults.object(forKey: "dl_library_folder") != nil)
    #expect(defaults.object(forKey: "dl_concurrent_downloads") != nil)
  }

  @Test
  func rejectsUnsupportedURLSchemesAndNonPositiveConcurrency() throws {
    let suiteName = "NPSCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SettingsStore(defaults: defaults)
    let ftp = try #require(URL(string: "ftp://catalog.example/games.tsv"))
    let remote = try #require(URL(string: "https://catalog.example/downloads"))

    #expect(throws: SettingsError.invalidCatalogueURL(.ps3Games, ftp.absoluteString)) {
      try store.setCatalogueURL(ftp, for: .ps3Games)
    }
    #expect(throws: SettingsError.invalidDownloadDirectory(remote)) {
      try store.setDownloadDirectory(remote)
    }
    #expect(throws: SettingsError.invalidConcurrency(0)) { try store.setConcurrentDownloads(0) }
    #expect(store.snapshot().concurrentDownloads == 3)
  }

  @Test
  func invalidPersistedValuesFallBackWithoutDeletingOtherSettings() throws {
    let suiteName = "NPSCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("ftp://catalog.example/games.tsv", forKey: CatalogSource.psxGames.rawValue)
    defaults.set(0, forKey: "dl_concurrent_downloads")
    defaults.set(false, forKey: "xt_keep_pkg")

    let settings = SettingsStore(defaults: defaults).snapshot()

    #expect(settings.catalogueURLs[.psxGames] == CatalogSource.psxGames.defaultURL)
    #expect(settings.concurrentDownloads == 3)
    #expect(!settings.extraction.keepPackage)
    #expect(
      defaults.string(forKey: CatalogSource.psxGames.rawValue) == "ftp://catalog.example/games.tsv"
    )
  }

  @Test
  func upgradesArchivedNoPayStationHTTPDefaultsToHTTPS() throws {
    let suiteName = "NPSCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(
      URL(string: "http://nopaystation.com/tsv/PSV_GAMES.tsv"),
      forKey: CatalogSource.psvGames.rawValue
    )

    let migratedURL = SettingsStore(defaults: defaults).catalogueURL(for: .psvGames)

    #expect(migratedURL.absoluteString == "https://nopaystation.com/tsv/PSV_GAMES.tsv")
    #expect(CatalogSource.psvGames.defaultURL.scheme == "https")
  }

  @Test
  func newPSMAndPSPDLCFeedsAreHTTPSDefaultsAlongsideExistingSources() throws {
    let suiteName = "NPSCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = SettingsStore(defaults: defaults).snapshot()

    #expect(
      CatalogSource.psmGames.defaultURL.absoluteString
        == "https://nopaystation.com/tsv/PSM_GAMES.tsv"
    )
    #expect(
      CatalogSource.pspDLCs.defaultURL.absoluteString == "https://nopaystation.com/tsv/PSP_DLCS.tsv"
    )
    #expect(settings.catalogueURLs[.psmGames] == CatalogSource.psmGames.defaultURL)
    #expect(settings.catalogueURLs[.pspDLCs] == CatalogSource.pspDLCs.defaultURL)
    #expect(settings.catalogueURLs[.psvGames] == CatalogSource.psvGames.defaultURL)
    #expect(settings.catalogueURLs[.ps3Games] == CatalogSource.ps3Games.defaultURL)
    #expect(settings.catalogueURLs[.compatPacks] == CatalogSource.compatPacks.defaultURL)
    #expect(settings.catalogueURLs[.compatPatch] == CatalogSource.compatPatch.defaultURL)
  }

  @Test
  func preservesLegacyFileCatalogueURLs() throws {
    let suiteName = "NPSCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SettingsStore(defaults: defaults)
    let fileURL = URL(fileURLWithPath: "/tmp/nps-catalogues/PS3_GAMES.tsv")

    defaults.set(fileURL.absoluteString, forKey: CatalogSource.ps3Games.rawValue)
    try store.setCatalogueURL(fileURL, for: .psvGames)

    #expect(store.catalogueURL(for: .ps3Games) == fileURL)
    #expect(store.catalogueURL(for: .psvGames) == fileURL)
    #expect(store.catalogueURL(for: .ps3Games).isFileURL)
    #expect(store.snapshot().catalogueURLs[.ps3Games] == fileURL)
  }

  @Test
  func usesLegacyDownloadLocationForLibraryWhenNoFolderOverrideExists() throws {
    let suiteName = "NPSCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let legacyLocation = URL(fileURLWithPath: "/Volumes/NPS Library", isDirectory: true)
    defaults.set(legacyLocation, forKey: "dl_library_location")

    let settings = SettingsStore(defaults: defaults).snapshot()

    #expect(settings.downloadDirectory == legacyLocation.standardizedFileURL)
    #expect(settings.downloadLibraryDirectory == legacyLocation.standardizedFileURL)
  }

  @Test
  func explicitDownloadLibraryFolderOverridesLegacyLocation() throws {
    let suiteName = "NPSCoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let legacyLocation = URL(fileURLWithPath: "/Volumes/NPS Library", isDirectory: true)
    let explicitFolder = URL(fileURLWithPath: "/Volumes/Extracted Games", isDirectory: true)
    defaults.set(legacyLocation, forKey: "dl_library_location")
    defaults.set(explicitFolder, forKey: "dl_library_folder")

    let settings = SettingsStore(defaults: defaults).snapshot()

    #expect(settings.downloadDirectory == legacyLocation.standardizedFileURL)
    #expect(settings.downloadLibraryDirectory == explicitFolder.standardizedFileURL)
  }
}
