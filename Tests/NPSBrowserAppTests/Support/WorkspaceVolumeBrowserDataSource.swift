import Foundation
import NPSCore
import NPSDownloads
@testable import NPSBrowserApp

actor WorkspaceVolumeSnapshotFixture {
  private let extractedDirectory: URL
  private var loads = 0
  private var completedLoads = 0
  private var replacementDownloads: [DownloadEntry]?
  private var shouldDelayNextLoad = false
  private var delayedLoadContinuation: CheckedContinuation<Void, Never>?
  private var streamObserverCountValue = 0
  private var streamContinuation: AsyncStream<[DownloadEntry]>.Continuation?
  private var publishesRequestedJobs = false
  private var requestedJobs: [DownloadEntry] = []

  init(extractedDirectory: URL) { self.extractedDirectory = extractedDirectory }

  func loadDownloads() async -> [DownloadEntry] {
    loads += 1
    var isDirectory: ObjCBool = false
    let isAvailable =
      FileManager.default.fileExists(atPath: extractedDirectory.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
    let downloads =
      (replacementDownloads ?? [
        DownloadEntry(
          id: "completed-volume-job",
          title: "Completed Game",
          detail: "PCSE12345",
          state: .complete,
          progress: 1,
          completedFile: isAvailable ? extractedDirectory : nil,
          titleID: "PCSE12345"
        ),
        DownloadEntry(
          id: "queued-volume-job",
          title: "Another Game",
          detail: "PCSE54321",
          state: .queued,
          progress: 0,
          completedFile: nil,
          titleID: "PCSE54321"
        ),
      ]) + requestedJobs
    if shouldDelayNextLoad {
      shouldDelayNextLoad = false
      await withCheckedContinuation { continuation in delayedLoadContinuation = continuation }
    }
    completedLoads += 1
    return downloads
  }

  func loadCount() -> Int { loads }
  func completedLoadCount() -> Int { completedLoads }
  func streamObserverCount() -> Int { streamObserverCountValue }

  func observeDownloads() -> AsyncStream<[DownloadEntry]> {
    let pair = AsyncStream<[DownloadEntry]>.makeStream()
    streamObserverCountValue += 1
    streamContinuation = pair.continuation
    return pair.stream
  }

  func emit(_ snapshot: [DownloadEntry]) { streamContinuation?.yield(snapshot) }

  func replaceDownloads(_ downloads: [DownloadEntry]) { replacementDownloads = downloads }

  /// Mirrors the coordinator, which publishes a new job before enqueue returns.
  func publishRequestedJobs() { publishesRequestedJobs = true }

  func recordRequestedJob(_ entry: BrowserEntry, jobID: UUID) {
    guard publishesRequestedJobs else { return }
    requestedJobs.append(
      DownloadEntry(
        id: jobID.uuidString,
        title: entry.title,
        detail: entry.titleID,
        state: .queued,
        progress: 0,
        completedFile: nil,
        titleID: entry.titleID
      )
    )
  }

  func requestedJobIDs() -> [UUID] { requestedJobs.compactMap { UUID(uuidString: $0.id) } }

  func delayNextLoad() { shouldDelayNextLoad = true }

  func releaseDelayedLoad() {
    delayedLoadContinuation?.resume()
    delayedLoadContinuation = nil
  }
}

actor WorkspaceEnqueueGate {
  private var startedCount = 0
  private var releasedEnqueues: Set<Int> = []
  private var enqueueContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private var startWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

  func suspendEnqueue() async {
    startedCount += 1
    let enqueueNumber = startedCount
    guard !releasedEnqueues.contains(enqueueNumber) else { return }
    await withCheckedContinuation { continuation in
      enqueueContinuations[enqueueNumber] = continuation
      let waiters = startWaiters.removeValue(forKey: enqueueNumber) ?? []
      waiters.forEach { $0.resume() }
    }
  }

  func waitUntilStarted(_ count: Int = 1) async {
    guard startedCount < count else { return }
    await withCheckedContinuation { startWaiters[count, default: []].append($0) }
  }

  func release(_ enqueueNumber: Int) {
    releasedEnqueues.insert(enqueueNumber)
    enqueueContinuations.removeValue(forKey: enqueueNumber)?.resume()
  }

  func release() {
    guard startedCount > 0 else { return }
    for enqueueNumber in 1...startedCount { release(enqueueNumber) }
  }
}

struct WorkspaceVolumeBrowserDataSource: BrowserDataSource {
  let fixture: WorkspaceVolumeSnapshotFixture
  let enqueueGate: WorkspaceEnqueueGate

  func loadCatalogue() throws -> [BrowserEntry] { [workspaceRefreshCatalogueEntry()] }
  func refreshCatalogue() throws -> [BrowserEntry] { [workspaceRefreshCatalogueEntry()] }
  func loadBookmarkedIDs() throws -> Set<String> { [] }
  func setBookmarked(_ entry: BrowserEntry, isBookmarked: Bool) throws {}
  func enqueue(_ entry: BrowserEntry, jobID: UUID) async throws {
    await fixture.recordRequestedJob(entry, jobID: jobID)
    await enqueueGate.suspendEnqueue()
  }
  func enqueueRAP(_ entry: BrowserEntry, jobID: UUID) throws {}
  func enqueueUpdate(_ entry: BrowserEntry, jobID: UUID) throws {}
  func loadBookmarksForExport() throws -> [Bookmark] { [] }
  func loadDownloads() async throws -> [DownloadEntry] { await fixture.loadDownloads() }
  func observeDownloads() async -> AsyncStream<[DownloadEntry]> { await fixture.observeDownloads() }
  func completedFileURL(for downloadID: String) throws -> URL {
    throw DownloadCoordinatorError.downloadUnavailable(.text("The fixture file is not available."))
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

func workspaceRefreshCatalogueEntry(
  id: String = "volume-refresh-enqueue",
  title: String = "Pending Game",
  titleID: String = "PCSE11223",
  packageURL: URL = URL(string: "https://example.test/pending.pkg")!
) -> BrowserEntry {
  BrowserEntry(
    id: id,
    title: title,
    titleID: titleID,
    console: "PS Vita",
    consoleCode: "PSV",
    category: "Game",
    region: "US",
    fileSize: nil,
    packageURL: packageURL,
    sha256: nil,
    contentID: nil
  )
}
