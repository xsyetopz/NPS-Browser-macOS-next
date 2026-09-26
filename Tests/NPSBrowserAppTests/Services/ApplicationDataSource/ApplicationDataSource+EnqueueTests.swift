import Foundation
import NPSCore
import NPSDownloads
import NPSPersistence
import Testing
@testable import NPSBrowserApp

@Test(.sourceEnglish)
func cpackEntryQueuesCompositeRequestWithOnlyItsMatchingCpatch() throws {
  let packURL = try #require(URL(string: "https://cdn.example/PCSB01101.ppk"))
  let matchingPatchURL = try #require(URL(string: "https://cdn.example/patch/PCSB01101.ppk"))
  let otherPatchURL = try #require(URL(string: "https://cdn.example/patch/PCSE99999.ppk"))
  let packs = [
    CompatibilityPack(
      titleID: "PCSB01101",
      downloadURL: packURL,
      kind: .pack,
      displayName: "Example Pack"
    ),
    CompatibilityPack(
      titleID: "PCSB01101",
      downloadURL: matchingPatchURL,
      kind: .patch,
      displayName: "Example Patch"
    ),
    CompatibilityPack(
      titleID: "PCSE99999",
      downloadURL: otherPatchURL,
      kind: .patch,
      displayName: "Unrelated Patch"
    ),
  ]

  let entries = ApplicationDataSource.compatibilityEntries(from: packs)
  let packEntry = try #require(entries.first { $0.compatibilityPackKind == .pack })
  let request = try ApplicationDataSource.compatibilityPackRequest(for: packEntry)

  #expect(request.titleID == "PCSB01101")
  #expect(request.title == "Example Pack")
  #expect(request.packURL == packURL)
  #expect(request.patchURL == matchingPatchURL)
}

@Test(.sourceEnglish)
func enqueueingCPackPersistsPackAndMatchingPatchInOneDownloadJob() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "NPSAppCompatibility-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let packURL = try #require(URL(string: "http://127.0.0.1:1/PCSB01101.ppk"))
  let patchURL = try #require(URL(string: "http://127.0.0.1:1/patch/PCSB01101.ppk"))
  let catalogue = try RealmCatalogueStore(fileURL: root.appendingPathComponent("catalogue.realm"))
  let suiteName = "NPSAppCompatibility-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let settings = SettingsStore(defaults: defaults)
  let downloadDirectory = root.appendingPathComponent("Downloads", isDirectory: true)
  let coordinator = try DownloadCoordinator(
    preferences: {
      DownloadPreferences(downloadDirectory: downloadDirectory, concurrentDownloads: 1)
    },
    persistenceURL: root.appendingPathComponent("downloads.plist")
  )
  let dataSource = ApplicationDataSource(
    settings: settings,
    catalogue: catalogue,
    downloads: coordinator
  )
  let packEntry = BrowserEntry(
    id: "pack-PCSB01101",
    title: "Example Pack",
    titleID: "PCSB01101",
    console: "PS Vita",
    consoleCode: "PSV",
    category: "CPack",
    region: "",
    fileSize: nil,
    packageURL: packURL,
    sha256: nil,
    contentID: nil,
    isCompatibilityPack: true,
    compatibilityPackKind: .pack,
    compatibilityPatchURL: patchURL
  )

  try await dataSource.enqueue(packEntry, jobID: UUID())
  let job = try #require(await coordinator.snapshots().first)
  try? await coordinator.remove(job.id)

  #expect(job.request.titleID == "PCSB01101")
  #expect(job.request.sourceURL == packURL)
  #expect(job.request.compatibilityPatchURL == patchURL)
  #expect(job.request.fileExtension == "ppk")
  #expect(job.request.extractAfterDownload)
}

@Test(.sourceEnglish)
func patchOnlyLiveCompatibilityRowsQueueExtractablePPKJobs() async throws {
  let patchFeed = """
    patch/PCSE00640/PCSE00640-03_650-01_05-01_00.ppk=Shovel Knight
    patch/PCSE00491/PCSE00491-03_650-01_83-01_00.ppk=Minecraft: PlayStation Vita Edition
    """
  let feedPatches = try CatalogParser.parseCompatibilityPacks(patchFeed, kind: .patch)
  #expect(feedPatches.map(\.titleID) == ["PCSE00640", "PCSE00491"])
  #expect(
    feedPatches.map(\.displayName) == ["Shovel Knight", "Minecraft: PlayStation Vita Edition"]
  )
  let loopbackPatches = feedPatches.map { patch in
    CompatibilityPack(
      titleID: patch.titleID,
      downloadURL: URL(string: "http://127.0.0.1:1\(patch.downloadURL.path)")!,
      kind: patch.kind,
      displayName: patch.displayName
    )
  }

  let entries = ApplicationDataSource.compatibilityEntries(from: loopbackPatches)
  let root = try makeCompatibilityPatchDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let suiteName = "NPSCompatibilityPatch-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let (dataSource, coordinator) = try makeCompatibilityPatchDataSource(
    root: root,
    defaults: defaults
  )

  for (titleID, name) in [
    ("PCSE00640", "Shovel Knight"), ("PCSE00491", "Minecraft: PlayStation Vita Edition"),
  ] {
    let entry = try #require(entries.first { $0.titleID == titleID })
    #expect(entry.title == name)
    #expect(entry.compatibilityPackKind == .patch)
    #expect(entry.matchingPackURL == nil)
    #expect(entry.packageURL?.path.contains("/patch/\(titleID)/") == true)

    try await dataSource.enqueue(entry, jobID: UUID())
    let job = try #require(await coordinator.snapshots().first { $0.request.titleID == titleID })
    #expect(job.request.sourceURL == entry.packageURL)
    #expect(job.request.title == name)
    #expect(job.request.fileExtension == "ppk")
    #expect(job.request.extractAfterDownload)
    #expect(job.request.compatibilityPatchURL == nil)
    #expect(job.request.compatibilityPatchMode == .overlayExistingOutput)
    try await coordinator.remove(job.id)
  }
}

@Test(.sourceEnglish)
func selectingCPatchWithMatchingCPackQueuesTheCompositeInsteadOfPatchAlone() async throws {
  let packURL = try #require(URL(string: "http://127.0.0.1:1/PCSB01101.ppk"))
  let patchURL = try #require(
    URL(string: "http://127.0.0.1:1/patch/PCSB01101/PCSB01101-03_650-01_01-01_00.ppk")
  )
  let entries = ApplicationDataSource.compatibilityEntries(from: [
    CompatibilityPack(
      titleID: "PCSB01101",
      downloadURL: packURL,
      kind: .pack,
      displayName: "Example Pack"
    ),
    CompatibilityPack(
      titleID: "PCSB01101",
      downloadURL: patchURL,
      kind: .patch,
      displayName: "Example Pack Patch"
    ),
  ])
  let patchEntry = try #require(entries.first { $0.compatibilityPackKind == .patch })
  let packEntry = try #require(entries.first { $0.compatibilityPackKind == .pack })
  let patchRequest = try ApplicationDataSource.compatibilityPackRequest(for: patchEntry)
  let packRequest = try ApplicationDataSource.compatibilityPackRequest(for: packEntry)
  #expect(patchRequest == packRequest)
  let root = try makeCompatibilityPatchDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let suiteName = "NPSCompatibilityPatch-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let (dataSource, coordinator) = try makeCompatibilityPatchDataSource(
    root: root,
    defaults: defaults,
    extractAfterDownload: false
  )

  try await dataSource.enqueue(patchEntry, jobID: UUID())
  let job = try #require(await coordinator.snapshots().first { $0.request.titleID == "PCSB01101" })

  #expect(job.request.sourceURL == packURL)
  #expect(job.request.compatibilityPatchURL == patchURL)
  #expect(job.request.fileExtension == "ppk")
  #expect(!job.request.extractAfterDownload)
  #expect(job.request.title == "Example Pack")
  try await coordinator.remove(job.id)
}

@Test(.sourceEnglish)
func patchOnlyCompatibilityRowsRespectDisabledExtractionSetting() async throws {
  let feed = "patch/PCSE00640/PCSE00640-03_650-01_05-01_00.ppk=Shovel Knight"
  let patch = try #require(CatalogParser.parseCompatibilityPacks(feed, kind: .patch).first)
  let entry = try #require(ApplicationDataSource.compatibilityEntries(from: [patch]).first)
  let root = try makeCompatibilityPatchDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let suiteName = "NPSCompatibilityPatchNoExtract-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let (dataSource, coordinator) = try makeCompatibilityPatchDataSource(
    root: root,
    defaults: defaults,
    extractAfterDownload: false
  )

  try await dataSource.enqueue(entry, jobID: UUID())
  let job = try #require(await coordinator.snapshots().first { $0.request.titleID == "PCSE00640" })

  #expect(job.request.fileExtension == "ppk")
  #expect(!job.request.extractAfterDownload)
  #expect(job.request.compatibilityPatchURL == nil)
  #expect(job.request.compatibilityPatchMode == .overlayExistingOutput)
  try await coordinator.remove(job.id)
}

@Test(.sourceEnglish)
func ps3RAPCatalogueEntryQueuesToSavedLibraryWithoutExtraction() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "NPSRAP-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let rapURL = try #require(URL(string: "http://127.0.0.1:1/rap/NPUB12345.rap"))
  let item = CatalogItem(
    titleID: "NPUB12345",
    contentID: "UP0001-NPUB12345_00-EXAMPLE000000000",
    name: "Example / PS3: Game",
    packageURL: URL(string: "https://example.test/NPUB12345.pkg"),
    rap: "UP0001-NPUB12345_00-EXAMPLE000000000",
    rapDownloadURL: rapURL,
    consoleType: .PS3,
    fileType: .Game
  )
  let catalogue = try RealmCatalogueStore(fileURL: root.appendingPathComponent("catalogue.realm"))
  try await catalogue.replaceItems([item])

  let suiteName = "NPSRAP-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let settings = SettingsStore(defaults: defaults)
  let savedLibrary = root.appendingPathComponent("My RAP Library", isDirectory: true)
  try settings.setDownloadLibraryDirectory(savedLibrary)
  let coordinator = try DownloadCoordinator(
    preferences: {
      let snapshot = settings.snapshot()
      return DownloadPreferences(
        downloadDirectory: snapshot.downloadLibraryDirectory,
        concurrentDownloads: snapshot.concurrentDownloads
      )
    },
    persistenceURL: root.appendingPathComponent("downloads.plist")
  )
  let dataSource = ApplicationDataSource(
    settings: settings,
    catalogue: catalogue,
    downloads: coordinator
  )

  let catalogueEntries = try await dataSource.loadCatalogue()
  let entry = try #require(catalogueEntries.first)
  #expect(entry.rapDownloadURL == rapURL)
  #expect(entry.supportsRAPDownload)

  var invalidTitleIDEntry = entry
  invalidTitleIDEntry.titleID = "../NPUB12345"
  var invalidRequestWasRejected = false
  do { try await dataSource.enqueueRAP(invalidTitleIDEntry, jobID: UUID()) } catch {
    invalidRequestWasRejected = true
  }
  #expect(invalidRequestWasRejected)
  #expect(await coordinator.snapshots().isEmpty)

  try await dataSource.enqueueRAP(entry, jobID: UUID())
  let job = try #require(await coordinator.snapshots().first)
  let destination = try #require(job.destinationURL)
  try? await coordinator.remove(job.id)

  #expect(job.request.sourceURL == rapURL)
  #expect(job.request.titleID == "NPUB12345")
  #expect(job.request.fileExtension == "rap")
  #expect(!job.request.extractAfterDownload)
  #expect(job.destinationDirectory == savedLibrary.appendingPathComponent("PS3", isDirectory: true))
  #expect(destination.deletingLastPathComponent() == job.destinationDirectory)
  #expect(destination.lastPathComponent == "Example _ PS3_ Game RAP NPUB12345.rap")
  #expect(!destination.lastPathComponent.contains("/"))
}

private func makeCompatibilityPatchDataSource(
  root: URL,
  defaults: UserDefaults,
  extractAfterDownload: Bool = true
) throws -> (ApplicationDataSource, DownloadCoordinator) {
  let settings = SettingsStore(defaults: defaults)
  settings.updateExtractionSettings(
    ExtractionSettings(extractAfterDownload: extractAfterDownload, keepPackage: false)
  )
  try settings.setDownloadLibraryDirectory(
    root.appendingPathComponent("Library", isDirectory: true)
  )
  let catalogue = try RealmCatalogueStore(fileURL: root.appendingPathComponent("catalogue.realm"))
  let coordinator = try DownloadCoordinator(
    preferences: {
      let snapshot = settings.snapshot()
      return DownloadPreferences(
        downloadDirectory: snapshot.downloadLibraryDirectory,
        concurrentDownloads: snapshot.concurrentDownloads
      )
    },
    persistenceURL: root.appendingPathComponent("downloads.plist"),
    urlSessionConfiguration: .ephemeral
  )
  return (
    ApplicationDataSource(settings: settings, catalogue: catalogue, downloads: coordinator),
    coordinator
  )
}

@Test(.sourceEnglish)
func appUpdateFeedResolvesSignedMetadataAndPackageURL() throws {
  let metadataURL = try CatalogParser.updateXMLURL(for: "PCSA00007")
  let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <title_patch><tag><package version="01.00" url="https://example.test/update.pkg" /></tag></title_patch>
    """

  let packageURL = try CatalogParser.parseUpdateXML(xml)

  #expect(metadataURL.absoluteString.contains("/PCSA00007/"))
  #expect(metadataURL.lastPathComponent == "PCSA00007-ver.xml")
  #expect(packageURL == URL(string: "https://example.test/update.pkg"))
}
