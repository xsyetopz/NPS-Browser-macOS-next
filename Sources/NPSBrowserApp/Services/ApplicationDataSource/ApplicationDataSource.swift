import Foundation
import NPSCore
import NPSDownloads
import NPSPersistence

struct ApplicationDataSource: BrowserDataSource {
  let settings: SettingsStore
  let catalogue: RealmCatalogueStore
  let downloads: DownloadCoordinator

  init(settings: SettingsStore, catalogue: RealmCatalogueStore, downloads: DownloadCoordinator) {
    self.settings = settings
    self.catalogue = catalogue
    self.downloads = downloads
  }

  init() throws {
    let fileManager = FileManager.default
    let applicationSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("NPS Browser", isDirectory: true)
    let backups = applicationSupport.appendingPathComponent("RealmBackups", isDirectory: true)
    try fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)

    let settings = SettingsStore()
    let defaults = UserDefaults.standard
    let legacyDownloadListData = defaults.data(forKey: "downloads")
    let helper = Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Helpers", isDirectory: true).appendingPathComponent(
        "Cpkg2zip",
        isDirectory: false
      )
    let extractor = Pkg2ZipExtractor(executableURL: helper)
    let downloadStore = applicationSupport.appendingPathComponent("downloads.plist")
    let coordinator = try DownloadCoordinator(
      preferences: {
        let snapshot = settings.snapshot()
        return DownloadPreferences(
          downloadDirectory: snapshot.downloadLibraryDirectory,
          concurrentDownloads: snapshot.concurrentDownloads
        )
      },
      persistenceURL: downloadStore,
      extractor: extractor,
      legacyDownloadListData: legacyDownloadListData,
      legacyDownloadBackupDirectory: applicationSupport.appendingPathComponent(
        "LegacyDownloadBackups",
        isDirectory: true
      )
    )

    // Import the legacy queue before Realm is opened so migration failures
    // cannot interrupt its raw backup or leave the new queue partially saved.
    // Keep UserDefaults untouched: the archived app may still be writing a
    // newer queue; the coordinator's persisted archive digest prevents
    // removed jobs from being resurrected by an unchanged legacy queue.
    let catalogue = try RealmCatalogueStore(backupDirectory: backups)

    self.settings = settings
    self.catalogue = catalogue
    downloads = coordinator
  }
}
