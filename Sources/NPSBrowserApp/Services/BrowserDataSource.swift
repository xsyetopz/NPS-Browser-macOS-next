import Foundation
import NPSCore

protocol BrowserDataSource: Sendable {
  func loadCatalogue() async throws -> [BrowserEntry]
  func refreshCatalogue() async throws -> [BrowserEntry]
  func loadBookmarkedIDs() async throws -> Set<String>
  func setBookmarked(_ entry: BrowserEntry, isBookmarked: Bool) async throws
  /// `jobID` identifies the queued download in later snapshots. A request
  /// deduplicated against an active job keeps that job's ID instead.
  func enqueue(_ entry: BrowserEntry, jobID: UUID) async throws
  func enqueueRAP(_ entry: BrowserEntry, jobID: UUID) async throws
  func enqueueUpdate(_ entry: BrowserEntry, jobID: UUID) async throws
  func loadBookmarksForExport() async throws -> [Bookmark]
  func loadDownloads() async throws -> [DownloadEntry]
  func observeDownloads() async -> AsyncStream<[DownloadEntry]>
  func completedFileURL(for downloadID: String) async throws -> URL
  func controlDownload(_ downloadID: String, action: DownloadAction) async throws
  func loadPreferences() async throws -> BrowserPreferences
  func savePreferences(_ preferences: BrowserPreferences) async throws
  func pauseDownloads() async throws
}
