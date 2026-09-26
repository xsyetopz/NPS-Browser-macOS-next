import Foundation
import NPSCore

extension DownloadCoordinator {
  /// Add a package to the durable queue. Duplicate source URLs with the same
  /// equivalent request returns the existing job, including for rapid repeated taps.
  /// `jobID` lets a caller recognize the new job in snapshots published before
  /// this call returns; a deduplicated request keeps the existing job's ID.
  @discardableResult
  public func enqueue(
    _ request: DownloadJobRequest,
    jobID: UUID = UUID()
  ) throws -> DownloadSnapshot {
    try validate(request)
    if let existing = jobs.values.first(where: { $0.request == request && Self.isActive($0.state) })
    {
      return snapshot(for: existing)
    }

    let preferences = preferencesProvider()
    let root = preferences.downloadDirectory
    let volumeUUID = try? root.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    let consoleDirectory = root.appendingPathComponent(
      Self.safePathComponent(request.consoleType),
      isDirectory: true
    )
    let url = nextAvailableURL(for: request, in: consoleDirectory)
    let patchURL = request.compatibilityPatchURL.map { _ in
      nextAvailableURL(
        title: "\(request.fileNameTitle) CPatch",
        fileExtension: "ppk",
        in: consoleDirectory
      )
    }
    let now = Date()
    let job = PersistedDownload(
      id: jobID,
      request: request,
      state: .queued,
      progress: 0,
      bytesReceived: 0,
      destinationDirectory: consoleDirectory,
      destinationVolumeUUID: volumeUUID,
      destinationURL: url,
      verifiedPackage: false,
      compatibilityPatchDestinationURL: patchURL,
      compatibilityPatchVerified: false,
      activeTransfer: .primary,
      extractedDirectoryURL: nil,
      errorMessage: nil,
      resumeData: nil,
      createdAt: now,
      updatedAt: now
    )
    reservedPaths.insert(url.path)
    if let patchURL { reservedPaths.insert(patchURL.path) }
    do { try commit(job) } catch {
      reservedPaths.remove(url.path)
      if let patchURL { reservedPaths.remove(patchURL.path) }
      throw error
    }
    publish()
    scheduleQueuedJobs()
    return snapshot(for: jobs[job.id] ?? job)
  }

  /// Enqueues the historical CPack workflow as one durable job. A matching
  /// CPatch is downloaded after its pack and overlaid only when extraction is enabled.
  @discardableResult
  public func enqueueCompatibilityPack(
    _ request: CompatibilityPackRequest,
    jobID: UUID = UUID()
  ) throws -> DownloadSnapshot {
    if let existing = jobs.values.first(where: {
      $0.request.fileExtension.lowercased() == "ppk"
        && $0.request.extractAfterDownload == request.extractAfterDownload
        && $0.request.titleID == request.titleID && $0.request.sourceURL == request.packURL
        && $0.request.compatibilityPatchURL == request.patchURL && Self.isActive($0.state)
    }) {
      return snapshot(for: existing)
    }
    return try enqueue(
      DownloadJobRequest(
        sourceURL: request.packURL,
        title: request.title,
        consoleType: "PSV",
        titleID: request.titleID,
        fileExtension: "ppk",
        extractAfterDownload: request.extractAfterDownload,
        extractionOptions: PackageExtractionOptions(keepPackage: true),
        compatibilityPatchURL: request.patchURL
      ),
      jobID: jobID
    )
  }

  public func pause(_ id: UUID) throws {
    guard var job = jobs[id] else { throw DownloadCoordinatorError.missingJob(id) }
    guard job.state == .downloading || job.state == .queued else {
      throw DownloadCoordinatorError.invalidTransition(from: job.state, to: .paused)
    }
    job.state = .paused
    job.setError(nil)
    job.updatedAt = Date()
    try commit(job)
    if runningJobs.contains(id) { transferClient.pause(id: id) }
    publish()
  }

  public func resume(_ id: UUID) throws {
    guard var job = jobs[id] else { throw DownloadCoordinatorError.missingJob(id) }
    guard job.state == .paused else {
      throw DownloadCoordinatorError.invalidTransition(from: job.state, to: .queued)
    }
    guard job.resumeData != nil || job.bytesReceived == 0 else {
      job.state = .failed
      job.setError(DownloadCoordinatorError.invalidResumeData.localizedMessage)
      job.updatedAt = Date()
      try commit(job)
      publish()
      throw DownloadCoordinatorError.invalidResumeData
    }
    if job.resumeData == nil, job.bytesReceived == 0, runningJobs.contains(id) {
      deferredResumes.insert(id)
      return
    }
    job.state = .queued
    job.setError(nil)
    if job.resumeData == nil { job.progress = 0 }
    if job.resumeData == nil { job.bytesReceived = 0 }
    job.updatedAt = Date()
    try commit(job)
    publish()
    scheduleQueuedJobs()
  }

  /// A restart deliberately discards resume data and begins from byte zero.
  public func restart(_ id: UUID) throws {
    guard var job = jobs[id] else { throw DownloadCoordinatorError.missingJob(id) }
    guard job.state == .failed || (job.state == .paused && job.resumeData == nil) else {
      throw DownloadCoordinatorError.invalidTransition(from: job.state, to: .queued)
    }
    job.state = .queued
    job.progress = 0
    job.bytesReceived = 0
    job.setError(nil)
    job.resumeData = nil
    let oldURL = job.destinationURL
    if let oldURL { reservedPaths.remove(oldURL.path) }
    let oldPatchURL = job.compatibilityPatchDestinationURL
    if let oldPatchURL { reservedPaths.remove(oldPatchURL.path) }
    job.destinationURL = nextAvailableURL(for: job.request, in: job.destinationDirectory)
    job.compatibilityPatchDestinationURL =
      job.request.compatibilityPatchURL == nil
      ? nil
      : nextAvailableURL(
        title: "\(job.request.fileNameTitle) CPatch",
        fileExtension: "ppk",
        in: job.destinationDirectory
      )
    job.verifiedPackage = false
    job.compatibilityPatchVerified = false
    job.activeTransfer = .primary
    job.updatedAt = Date()
    if let newURL = job.destinationURL { reservedPaths.insert(newURL.path) }
    if let newPatchURL = job.compatibilityPatchDestinationURL {
      reservedPaths.insert(newPatchURL.path)
    }
    do { try commit(job) } catch {
      if let newURL = job.destinationURL { reservedPaths.remove(newURL.path) }
      if let newPatchURL = job.compatibilityPatchDestinationURL {
        reservedPaths.remove(newPatchURL.path)
      }
      if let oldURL { reservedPaths.insert(oldURL.path) }
      if let oldPatchURL { reservedPaths.insert(oldPatchURL.path) }
      throw error
    }
    publish()
    scheduleQueuedJobs()
  }

  public func remove(_ id: UUID) throws {
    guard let job = jobs[id] else { throw DownloadCoordinatorError.missingJob(id) }
    guard job.state != .extracting else {
      throw DownloadCoordinatorError.downloadUnavailable(
        LocalizedMessage("error.download.removalDuringExtraction")
      )
    }
    try commitRemoval(id)
    if runningJobs.contains(id) { transferClient.cancel(id: id) }
    if let installingURL = installingURLs.removeValue(forKey: id) {
      reservedPaths.remove(installingURL.path)
    }
    if let stagingURL = stagingURLs.removeValue(forKey: id) {
      try? FileManager.default.removeItem(at: stagingURL)
    }
    if let destinationURL = job.destinationURL { reservedPaths.remove(destinationURL.path) }
    if let patchURL = job.compatibilityPatchDestinationURL { reservedPaths.remove(patchURL.path) }
    publish()
  }

  func finish(_ id: UUID) {
    runningJobs.remove(id)
    if deferredResumes.remove(id) != nil, var job = jobs[id], job.state == .paused {
      if job.resumeData == nil, job.bytesReceived > 0 {
        job.state = .failed
        job.setError(DownloadCoordinatorError.invalidResumeData.localizedMessage)
      } else {
        job.state = .queued
        job.setError(nil)
        if job.resumeData == nil {
          job.progress = 0
          job.bytesReceived = 0
        }
      }
      job.updatedAt = Date()
      do { try commit(job) } catch {}
      publish()
    }
    if let current = jobs[id], current.state == .paused, current.resumeData == nil,
      current.bytesReceived > 0
    {
      var failed = current
      failed.state = .failed
      failed.setError(DownloadCoordinatorError.invalidResumeData.localizedMessage)
      failed.updatedAt = Date()
      do { try commit(failed) } catch {}
      publish()
    }
    scheduleQueuedJobs()
  }

  func scheduleQueuedJobs() {
    guard !isDrainingForShutdown else { return }
    let maxConcurrent = max(1, preferencesProvider().concurrentDownloads)
    while runningJobs.count < maxConcurrent,
      let next = sortedJobs().first(where: {
        $0.state == .queued && !runningJobs.contains($0.id)
          && !hasActiveCompatibilityOutputConflict($0)
      })
    {
      guard var job = jobs[next.id] else { continue }
      let id = job.id
      job.state = .downloading
      job.setError(nil)
      job.updatedAt = Date()
      do { try commit(job) } catch {
        publish()
        break
      }
      runningJobs.insert(id)
      publish()
      Task { await self.perform(id) }
    }
  }

  func hasActiveCompatibilityOutputConflict(_ job: PersistedDownload) -> Bool {
    guard job.request.fileExtension.lowercased() == "ppk", job.request.extractAfterDownload,
      let titleID = job.request.titleID
    else { return false }
    if jobs.values.contains(where: { candidate in
      candidate.id != job.id && candidate.state == .extracting
        && candidate.request.fileExtension.lowercased() == "ppk"
        && candidate.request.extractAfterDownload && candidate.request.titleID == titleID
    }) {
      return true
    }
    return runningJobs.contains { runningID in
      guard runningID != job.id else { return false }
      guard let running = jobs[runningID] else { return false }
      return running.request.fileExtension.lowercased() == "ppk"
        && running.request.extractAfterDownload && running.request.titleID == titleID
    }
  }

  private static func isActive(_ state: DownloadState) -> Bool {
    switch state {
    case .queued, .downloading, .paused, .verifying, .extracting: return true
    case .failed, .complete: return false
    }
  }
}
