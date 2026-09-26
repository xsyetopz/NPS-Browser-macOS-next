import Foundation
import NPSCore
import Testing
@testable import NPSBrowserApp

/// Serves fixed preferences and records every save.
actor RecordingPreferencesDataSource: BrowserDataSource {
  private let empty = EmptyBrowserDataSource()
  private var saved: [BrowserPreferences] = []

  func savedPreferences() -> BrowserPreferences? { saved.last }
  func saveCount() -> Int { saved.count }

  func loadPreferences() throws -> BrowserPreferences {
    if let last = saved.last { return last }
    var catalogueURLs = Dictionary(
      uniqueKeysWithValues: CatalogSource.allCases.map { ($0, $0.defaultURL) }
    )
    catalogueURLs[.psvGames] = URL(string: "https://mirror.example/PSV_GAMES.tsv")
    return BrowserPreferences(
      catalogueURLs: catalogueURLs,
      downloadDirectory: URL(fileURLWithPath: "/tmp/Loaded Downloads", isDirectory: true),
      concurrentDownloads: 6,
      extraction: ExtractionSettings(compressPSPISO: true, unpackPS3Packages: true),
      hideInvalidURLItems: true
    )
  }

  func savePreferences(_ preferences: BrowserPreferences) throws { saved.append(preferences) }

  func loadCatalogue() throws -> [BrowserEntry] { [] }
  func refreshCatalogue() throws -> [BrowserEntry] { [] }
  func loadBookmarkedIDs() throws -> Set<String> { [] }
  func setBookmarked(_ entry: BrowserEntry, isBookmarked: Bool) throws {}
  func enqueue(_ entry: BrowserEntry, jobID: UUID) throws {}
  func enqueueRAP(_ entry: BrowserEntry, jobID: UUID) throws {}
  func enqueueUpdate(_ entry: BrowserEntry, jobID: UUID) throws {}
  func loadBookmarksForExport() throws -> [Bookmark] { [] }
  func loadDownloads() throws -> [DownloadEntry] { [] }
  func observeDownloads() -> AsyncStream<[DownloadEntry]> { empty.observeDownloads() }
  func completedFileURL(for downloadID: String) throws -> URL {
    try empty.completedFileURL(for: downloadID)
  }
  func controlDownload(_ downloadID: String, action: DownloadAction) throws {}
  func pauseDownloads() throws {}
}

@MainActor
func waitForPreferencesForm(_ form: PreferencesFormView) async throws {
  for _ in 0..<200 {
    if form.downloadDirectoryPath == "/tmp/Loaded Downloads" { return }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  Issue.record("Timed out waiting for preferences to load")
}
