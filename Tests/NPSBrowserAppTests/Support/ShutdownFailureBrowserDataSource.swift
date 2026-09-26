import Foundation
import NPSCore
@testable import NPSBrowserApp

private func unusedFixtureMethod() -> Never { fatalError("unused") }

struct ShutdownFailureBrowserDataSource: BrowserDataSource {
  func loadCatalogue() throws -> [BrowserEntry] { unusedFixtureMethod() }
  func refreshCatalogue() throws -> [BrowserEntry] { unusedFixtureMethod() }
  func loadBookmarkedIDs() throws -> Set<String> { unusedFixtureMethod() }
  func setBookmarked(_ entry: BrowserEntry, isBookmarked: Bool) throws { unusedFixtureMethod() }
  func enqueue(_ entry: BrowserEntry, jobID: UUID) throws { unusedFixtureMethod() }
  func enqueueRAP(_ entry: BrowserEntry, jobID: UUID) throws { unusedFixtureMethod() }
  func enqueueUpdate(_ entry: BrowserEntry, jobID: UUID) throws { unusedFixtureMethod() }
  func loadBookmarksForExport() throws -> [Bookmark] { unusedFixtureMethod() }
  func loadDownloads() throws -> [DownloadEntry] { unusedFixtureMethod() }
  func observeDownloads() -> AsyncStream<[DownloadEntry]> { unusedFixtureMethod() }
  func completedFileURL(for downloadID: String) throws -> URL { unusedFixtureMethod() }
  func controlDownload(_ downloadID: String, action: DownloadAction) throws {
    unusedFixtureMethod()
  }
  func loadPreferences() throws -> BrowserPreferences { unusedFixtureMethod() }
  func savePreferences(_ preferences: BrowserPreferences) throws { unusedFixtureMethod() }
  func pauseDownloads() throws { throw ShutdownPersistenceFailure() }
}

private struct ShutdownPersistenceFailure: Error, LocalizedError {
  var errorDescription: String? {
    "The download queue could not be saved. Check available disk space and write permissions."
  }
}
