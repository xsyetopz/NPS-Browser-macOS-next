import Foundation
import NPSCore
import NPSDownloads
@testable import NPSBrowserApp

actor DelayedBookmarkFailureGate {
  private var writeCount = 0
  private var startedContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private var releaseContinuations: [Int: CheckedContinuation<Void, Never>] = [:]

  func suspendWrite() async {
    writeCount += 1
    let number = writeCount
    startedContinuations.removeValue(forKey: number)?.resume()
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      releaseContinuations[number] = continuation
    }
  }

  func waitForWrite(_ number: Int) async {
    guard writeCount < number else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      startedContinuations[number] = continuation
    }
  }

  func releaseWrite(_ number: Int) { releaseContinuations.removeValue(forKey: number)?.resume() }
}

struct DelayedBookmarkFailureDataSource: BrowserDataSource {
  let entries: [BrowserEntry]
  let gate: DelayedBookmarkFailureGate
  let initiallyBookmarkedIDs: Set<String>

  init(
    entries: [BrowserEntry],
    gate: DelayedBookmarkFailureGate,
    initiallyBookmarkedIDs: Set<String> = []
  ) {
    self.entries = entries
    self.gate = gate
    self.initiallyBookmarkedIDs = initiallyBookmarkedIDs
  }

  func loadCatalogue() throws -> [BrowserEntry] { entries }
  func refreshCatalogue() throws -> [BrowserEntry] { entries }
  func loadBookmarkedIDs() throws -> Set<String> { initiallyBookmarkedIDs }
  func setBookmarked(_ entry: BrowserEntry, isBookmarked: Bool) async throws {
    await gate.suspendWrite()
    throw BookmarkWriteFailure()
  }
  func enqueue(_ entry: BrowserEntry, jobID: UUID) throws {}
  func enqueueRAP(_ entry: BrowserEntry, jobID: UUID) throws {}
  func enqueueUpdate(_ entry: BrowserEntry, jobID: UUID) throws {}
  func loadBookmarksForExport() throws -> [Bookmark] { [] }
  func loadDownloads() throws -> [DownloadEntry] { [] }
  func observeDownloads() -> AsyncStream<[DownloadEntry]> { AsyncStream { $0.finish() } }
  func completedFileURL(for downloadID: String) throws -> URL {
    throw DownloadCoordinatorError.downloadUnavailable(.text("No completed file."))
  }
  func controlDownload(_ downloadID: String, action: DownloadAction) throws {}
  func loadPreferences() throws -> BrowserPreferences {
    BrowserPreferences(
      catalogueURLs: [:],
      downloadDirectory: FileManager.default.temporaryDirectory,
      concurrentDownloads: 1,
      extraction: ExtractionSettings(),
      hideInvalidURLItems: true
    )
  }
  func savePreferences(_ preferences: BrowserPreferences) throws {}
  func pauseDownloads() throws {}
}

private struct BookmarkWriteFailure: Error, LocalizedError {
  var errorDescription: String? { "The fixture bookmark write failed." }
}
