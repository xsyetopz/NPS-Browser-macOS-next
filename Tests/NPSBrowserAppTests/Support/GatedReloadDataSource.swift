import Foundation
import NPSCore
@testable import NPSBrowserApp

/// Holds the first catalogue load until `release()` and records every refresh.
actor GatedReloadDataSource: BrowserDataSource {
  private let empty = EmptyBrowserDataSource()
  private var loadCount = 0
  private var refreshes = 0
  private var gate: CheckedContinuation<Void, Never>?
  private var gateWaiters: [CheckedContinuation<Void, Never>] = []

  func refreshCount() -> Int { refreshes }

  /// Waits until the first load is parked on the gate.
  func waitUntilGated() async {
    if gate != nil { return }
    await withCheckedContinuation { gateWaiters.append($0) }
  }

  func release() {
    gate?.resume()
    gate = nil
  }

  func loadCatalogue() async throws -> [BrowserEntry] {
    loadCount += 1
    if loadCount == 1 {
      await withCheckedContinuation { continuation in
        gate = continuation
        let waiters = gateWaiters
        gateWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
      }
    }
    return [browserEntry(id: "gated-game", title: "Gated Game")]
  }

  func refreshCatalogue() throws -> [BrowserEntry] {
    refreshes += 1
    return [browserEntry(id: "gated-game", title: "Gated Game")]
  }

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
  func loadPreferences() throws -> BrowserPreferences { try empty.loadPreferences() }
  func savePreferences(_ preferences: BrowserPreferences) throws {}
  func pauseDownloads() throws {}
}
