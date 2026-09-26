import CryptoKit
import Foundation
import NPSCore

public actor DownloadCoordinator {
  let preferencesProvider: @Sendable () -> DownloadPreferences
  let store: DownloadStore
  let transferClient: URLSessionTransferClient
  let extractor: (any PackageExtractor)?
  var jobs: [UUID: PersistedDownload]
  var runningJobs: Set<UUID> = []
  var deferredResumes: Set<UUID> = []
  private(set) var isDrainingForShutdown = false
  /// Test seam: awaited after a transfer validates and before it is installed.
  var afterValidation: (@Sendable (UUID) async -> Void)?
  var reservedPaths: Set<String> = []
  var stagingURLs: [UUID: URL] = [:]
  var installingURLs: [UUID: URL] = [:]
  var updateContinuations: [UUID: AsyncStream<[DownloadSnapshot]>.Continuation] = [:]
  var persistenceError: String?

  /// `persistenceURL` should be in the app's Application Support directory.
  /// An unreadable/corrupt store is surfaced; it is never deleted or replaced.
  @preconcurrency
  public init(
    preferences: @escaping @Sendable () -> DownloadPreferences,
    persistenceURL: URL,
    extractor: (any PackageExtractor)? = nil,
    urlSessionConfiguration: URLSessionConfiguration = .default,
    legacyDownloadListData: Data? = nil,
    legacyDownloadBackupDirectory: URL? = nil
  ) throws {
    preferencesProvider = preferences
    store = DownloadStore(fileURL: persistenceURL)
    transferClient = URLSessionTransferClient(configuration: urlSessionConfiguration)
    self.extractor = extractor

    let backupDirectory =
      legacyDownloadBackupDirectory
      ?? persistenceURL.deletingLastPathComponent().appendingPathComponent(
        "LegacyDownloadBackups",
        isDirectory: true
      )
    let importLedgerURL = LegacyDownloadImportLedger.url(nextTo: persistenceURL)
    let currentLegacyDigest: String?
    let recordedLegacyDigest: String?
    if let legacyDownloadListData {
      try LegacyDownloadMigration.backupRaw(legacyDownloadListData, in: backupDirectory)
      currentLegacyDigest = LegacyDownloadMigration.fingerprint(legacyDownloadListData)
      recordedLegacyDigest = try LegacyDownloadImportLedger.read(at: importLedgerURL)
    } else {
      currentLegacyDigest = nil
      recordedLegacyDigest = nil
    }
    let stored = try store.load()
    let restored: [PersistedDownload]
    if let legacyDownloadListData, currentLegacyDigest != recordedLegacyDigest {
      restored = try LegacyDownloadMigration.merge(
        data: legacyDownloadListData,
        destinationRoot: preferencesProvider().downloadDirectory,
        existing: stored
      )
    } else {
      restored = stored
    }
    var normalized: [UUID: PersistedDownload] = [:]
    for var job in restored {
      if job.activeTransfer == nil { job.activeTransfer = .primary }
      switch job.state {
      case .downloading:
        if job.resumeData != nil {
          job.state = .paused
          job.setError(LocalizedMessage("error.download.restoredPaused"))
        } else {
          job.state = .failed
          job.setError(DownloadCoordinatorError.invalidResumeData.localizedMessage)
        }
      case .verifying:
        job.state = .failed
        job.setError(LocalizedMessage("error.download.closedWhileVerifying"))
      case .extracting:
        job.state = .failed
        job.setError(LocalizedMessage("error.download.closedDuringExtraction"))
      default: break
      }
      job.updatedAt = Date()
      normalized[job.id] = job
    }
    jobs = normalized
    reservedPaths = Set(normalized.values.compactMap { $0.destinationURL?.path })
    reservedPaths.formUnion(
      normalized.values.compactMap { $0.compatibilityPatchDestinationURL?.path }
    )
    try store.save(Array(normalized.values))
    if let currentLegacyDigest, currentLegacyDigest != recordedLegacyDigest {
      // Record the digest only after the atomically replaced native queue
      // contains the imported jobs. On failure, startup stops and retry is
      // safe: duplicate IDs/destinations merge without overwriting jobs.
      try LegacyDownloadImportLedger.write(currentLegacyDigest, to: importLedgerURL)
    }
    Task { await self.scheduleRestoredJobs() }
  }

  public func snapshots() -> [DownloadSnapshot] { sortedJobs().map(snapshot(for:)) }

  /// A stream emits its current snapshot immediately, then on each state or
  /// progress change. UI clients should consume it from their own task.
  public func updates() -> AsyncStream<[DownloadSnapshot]> {
    let observerID = UUID()
    return AsyncStream { continuation in
      updateContinuations[observerID] = continuation
      continuation.yield(sortedJobs().map(snapshot(for:)))
      continuation.onTermination = { @Sendable [weak self] _ in
        guard let self else { return }
        Task { await self.removeObserver(observerID) }
      }
    }
  }

  /// Returns the actual verified package URL, not a reconstructed title path.
  public func revealURL(for id: UUID) -> URL? { jobs[id]?.snapshot.completedURL }

  func setAfterValidation(_ hook: (@Sendable (UUID) async -> Void)?) { afterValidation = hook }

  /// Call during orderly app shutdown. Resume data is saved before this returns
  /// where the server and URLSession can produce it; otherwise jobs are failed
  /// with an explicit restart instruction on restore.
  public func pauseAll() async throws {
    isDrainingForShutdown = true
    let ids = runningJobs
    do { for id in ids where jobs[id]?.state == .downloading { try pause(id) } } catch {
      // A failed durable pause must leave its transfer running and must
      // cancel the shutdown attempt. Reopen scheduling for the app that
      // remains active, then let the caller present the save error.
      isDrainingForShutdown = false
      scheduleQueuedJobs()
      throw error
    }
    while !runningJobs.isEmpty { try? await Task.sleep(nanoseconds: 50_000_000) }
  }

  private func scheduleRestoredJobs() { scheduleQueuedJobs() }

  private func removeObserver(_ id: UUID) { updateContinuations.removeValue(forKey: id) }

}
