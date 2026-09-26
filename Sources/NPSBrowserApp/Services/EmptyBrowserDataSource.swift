import Foundation
import NPSCore
import NPSDownloads

struct EmptyBrowserDataSource: BrowserDataSource {
  var previewEntries: [BrowserEntry] = []

  func loadCatalogue() throws -> [BrowserEntry] { previewEntries }
  func refreshCatalogue() throws -> [BrowserEntry] { previewEntries }
  func loadBookmarkedIDs() throws -> Set<String> { [] }
  func setBookmarked(_ entry: BrowserEntry, isBookmarked: Bool) throws {}
  func enqueue(_ entry: BrowserEntry, jobID: UUID) throws {}
  func enqueueRAP(_ entry: BrowserEntry, jobID: UUID) throws {
    throw DownloadCoordinatorError.downloadUnavailable(LocalizedMessage("error.enqueue.rapPreview"))
  }
  func enqueueUpdate(_ entry: BrowserEntry, jobID: UUID) throws {
    throw DownloadCoordinatorError.downloadUnavailable(
      LocalizedMessage("error.enqueue.updatePreview")
    )
  }
  func loadBookmarksForExport() throws -> [Bookmark] { [] }
  func loadDownloads() throws -> [DownloadEntry] { [] }
  func observeDownloads() -> AsyncStream<[DownloadEntry]> {
    AsyncStream { continuation in
      continuation.yield([])
      continuation.finish()
    }
  }
  func completedFileURL(for downloadID: String) throws -> URL {
    throw DownloadCoordinatorError.downloadUnavailable(LocalizedMessage("error.reveal.missingFile"))
  }
  func controlDownload(_ downloadID: String, action: DownloadAction) throws {}
  func loadPreferences() throws -> BrowserPreferences {
    BrowserPreferences(
      catalogueURLs: Dictionary(
        uniqueKeysWithValues: CatalogSource.allCases.map { ($0, $0.defaultURL) }
      ),
      downloadDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Downloads",
        isDirectory: true
      ),
      concurrentDownloads: 3,
      extraction: ExtractionSettings(),
      hideInvalidURLItems: true
    )
  }
  func savePreferences(_ preferences: BrowserPreferences) throws {}
  func pauseDownloads() throws {}
}
