import Foundation
import NPSCore
@testable import NPSBrowserApp

actor SlowUpdateLookup {
  private var started = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var updateContinuation: CheckedContinuation<Void, any Error>?
  private var normalEnqueueStarted = false
  private var normalEnqueueWaiters: [CheckedContinuation<Void, Never>] = []
  private var normalEnqueueContinuation: CheckedContinuation<Void, any Error>?
  private var downloads: [DownloadEntry]
  private var streamContinuations: [UUID: AsyncStream<[DownloadEntry]>.Continuation] = [:]
  private var controlledActions: [DownloadAction] = []

  init(downloads: [DownloadEntry] = []) { self.downloads = downloads }

  func waitForUpdateLookup() async throws {
    try await withCheckedThrowingContinuation { continuation in
      updateContinuation = continuation
      started = true
      let waiters = startWaiters
      startWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func waitForNormalEnqueue() async throws {
    try await withCheckedThrowingContinuation { continuation in
      normalEnqueueContinuation = continuation
      normalEnqueueStarted = true
      let waiters = normalEnqueueWaiters
      normalEnqueueWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }

  func waitUntilNormalEnqueueStarted() async {
    if normalEnqueueStarted { return }
    await withCheckedContinuation { normalEnqueueWaiters.append($0) }
  }

  func recordControl(_ action: DownloadAction) { controlledActions.append(action) }

  func controlCount() -> Int { controlledActions.count }

  func waitForControlCount(_ count: Int) async {
    // AppKit window setup can occupy the main actor while unrelated Swift
    // Testing cases run concurrently; give queued UI commands time to run.
    for _ in 0..<1_000 {
      if controlledActions.count >= count { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func loadDownloads() -> [DownloadEntry] { downloads }

  func initialUpdates() -> AsyncStream<[DownloadEntry]> {
    let identifier = UUID()
    let pair = AsyncStream<[DownloadEntry]>.makeStream()
    streamContinuations[identifier] = pair.continuation
    pair.continuation.yield(downloads)
    pair.continuation.onTermination = { @Sendable [weak self] _ in
      Task { await self?.removeObserver(identifier) }
    }
    return pair.stream
  }

  func finish(with downloads: [DownloadEntry]) {
    self.downloads = downloads
    finishStreams(with: downloads)
    updateContinuation?.resume()
    updateContinuation = nil
  }

  func finishNormalEnqueue(with downloads: [DownloadEntry]) {
    self.downloads = downloads
    finishStreams(with: downloads)
    normalEnqueueContinuation?.resume()
    normalEnqueueContinuation = nil
  }

  func fail(_ error: any Error) {
    finishStreams()
    updateContinuation?.resume(throwing: error)
    updateContinuation = nil
  }

  private func finishStreams(with downloads: [DownloadEntry]? = nil) {
    for continuation in streamContinuations.values {
      if let downloads { continuation.yield(downloads) }
      continuation.finish()
    }
    streamContinuations.removeAll()
  }

  private func removeObserver(_ identifier: UUID) {
    streamContinuations.removeValue(forKey: identifier)
  }
}

struct SlowUpdateDataSource: BrowserDataSource {
  let lookup: SlowUpdateLookup

  func loadCatalogue() throws -> [BrowserEntry] { [] }
  func refreshCatalogue() throws -> [BrowserEntry] { [] }
  func loadBookmarkedIDs() throws -> Set<String> { [] }
  func setBookmarked(_ entry: BrowserEntry, isBookmarked: Bool) throws {}
  func enqueue(_ entry: BrowserEntry, jobID: UUID) async throws {
    try await lookup.waitForNormalEnqueue()
  }
  func enqueueRAP(_ entry: BrowserEntry, jobID: UUID) async throws {
    try await lookup.waitForNormalEnqueue()
  }
  func enqueueUpdate(_ entry: BrowserEntry, jobID: UUID) async throws {
    try await lookup.waitForUpdateLookup()
  }
  func loadBookmarksForExport() throws -> [Bookmark] { [] }
  func loadDownloads() async throws -> [DownloadEntry] { await lookup.loadDownloads() }
  func observeDownloads() async -> AsyncStream<[DownloadEntry]> { await lookup.initialUpdates() }
  func completedFileURL(for downloadID: String) throws -> URL { throw TestError.unused }
  func controlDownload(_ downloadID: String, action: DownloadAction) async throws {
    await lookup.recordControl(action)
  }
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

enum TestError: Error { case unused, lookupFailed }
