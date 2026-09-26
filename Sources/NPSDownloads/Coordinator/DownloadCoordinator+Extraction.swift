import Foundation
import NPSCore

extension DownloadCoordinator {
  /// Re-runs extraction from an already verified package without re-downloading.
  public func retryExtraction(_ id: UUID) async throws {
    if jobs[id]?.state == .failed, jobs[id]?.request.fileExtension.lowercased() == "ppk",
      runningJobs.contains(id)
    {
      while runningJobs.contains(id) {
        try await Task.sleep(nanoseconds: 1_000_000)
        guard jobs[id] != nil else { throw DownloadCoordinatorError.missingJob(id) }
      }
    }
    guard var job = jobs[id] else { throw DownloadCoordinatorError.missingJob(id) }
    guard job.state == .failed, job.verifiedPackage == true, let packageURL = job.destinationURL,
      FileManager.default.fileExists(atPath: packageURL.path)
    else { throw DownloadCoordinatorError.invalidTransition(from: job.state, to: .extracting) }
    let isCompatibilityArchive = job.request.fileExtension.lowercased() == "ppk"
    if isCompatibilityArchive, hasActiveCompatibilityOutputConflict(job) {
      throw DownloadCoordinatorError.downloadUnavailable(
        LocalizedMessage("error.download.rePatchBusy")
      )
    }
    let patchPackageURL: URL?
    if job.request.compatibilityPatchURL != nil {
      guard job.compatibilityPatchVerified == true,
        let patchURL = job.compatibilityPatchDestinationURL,
        FileManager.default.fileExists(atPath: patchURL.path)
      else {
        throw DownloadCoordinatorError.downloadUnavailable(
          LocalizedMessage("error.download.patchNotVerified")
        )
      }
      patchPackageURL = patchURL
    } else {
      patchPackageURL = nil
    }
    guard job.request.extractAfterDownload else {
      throw DownloadCoordinatorError.downloadUnavailable(
        LocalizedMessage("error.download.extractionNotSelected")
      )
    }
    if !isCompatibilityArchive, extractor == nil {
      throw DownloadCoordinatorError.downloadUnavailable(
        LocalizedMessage("error.download.noExtractorPackageKept")
      )
    }
    job.state = .extracting
    job.setError(nil)
    job.updatedAt = Date()
    try commit(job)
    runningJobs.insert(id)
    defer { finish(id) }
    publish()
    let extracted: URL
    do {
      if isCompatibilityArchive {
        guard let titleID = job.request.titleID else {
          throw DownloadCoordinatorError.downloadUnavailable(
            LocalizedMessage("error.download.missingRePatchTitleID")
          )
        }
        if job.request.compatibilityPatchMode == .overlayExistingOutput {
          guard job.request.compatibilityPatchURL == nil else {
            throw DownloadCoordinatorError.invalidRequest(
              LocalizedMessage("error.download.overlayWithPatchURL")
            )
          }
          extracted = try await CompatibilityPackExtractor().applyPatch(
            patchURL: packageURL,
            titleID: titleID,
            destinationDirectory: job.destinationDirectory
          )
        } else {
          extracted = try await CompatibilityPackExtractor().extract(
            packURL: packageURL,
            patchURL: patchPackageURL,
            titleID: titleID,
            destinationDirectory: job.destinationDirectory
          )
        }
      } else if let extractor {
        extracted = try await extractor.extract(
          packageURL: packageURL,
          request: job.request,
          destinationDirectory: job.destinationDirectory
        )
      } else {
        throw DownloadCoordinatorError.downloadUnavailable(
          LocalizedMessage("error.download.noExtractor")
        )
      }
    } catch {
      if isPersistenceFailure(error) {
        publish()
        throw error
      }
      guard var current = jobs[id] else { throw error }
      current.state = .failed
      current.setError(LocalizedMessage(error))
      current.updatedAt = Date()
      do { try commit(current) } catch {
        publish()
        throw error
      }
      publish()
      throw error
    }
    guard jobs[id] != nil else {
      try? FileManager.default.removeItem(at: extracted)
      return
    }
    try completeExtraction(id, extractedDirectoryURL: extracted)
  }

  private func removePackageIfConfigured(_ job: PersistedDownload) -> LocalizedMessage? {
    guard !job.request.extractionOptions.keepPackage else { return nil }
    var failures: [String] = []
    let packageURLs = [job.destinationURL, job.compatibilityPatchDestinationURL].compactMap { $0 }
    for packageURL in packageURLs {
      do { try FileManager.default.removeItem(at: packageURL) } catch {
        failures.append("\(packageURL.lastPathComponent): \(error.localizedDescription)")
      }
    }
    return failures.isEmpty
      ? nil
      : LocalizedMessage(
        "error.download.archiveCleanupFailed",
        .text(failures.joined(separator: "; "))
      )
  }

  func completeExtraction(_ id: UUID, extractedDirectoryURL: URL) throws {
    guard var job = jobs[id] else { return }
    job.extractedDirectoryURL = extractedDirectoryURL
    job.state = .complete
    job.setError(nil)
    job.progress = 1
    job.updatedAt = Date()
    // Persist success before optionally deleting the source package. If the
    // process stops between these steps, the package is retained, not lost.
    try commit(job)
    if let warning = removePackageIfConfigured(job) {
      job.setError(warning)
      job.updatedAt = Date()
      try commit(job)
    }
    publish()
  }
}
