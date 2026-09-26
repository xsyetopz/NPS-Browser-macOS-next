import Foundation
import NPSCore

extension DownloadCoordinator {
  private func persist() throws {
    do {
      try store.save(Array(jobs.values))
      persistenceError = nil
    } catch {
      persistenceError = error.localizedDescription
      throw DownloadCoordinatorError.persistenceFailure(error.localizedDescription)
    }
  }

  func publish() {
    let snapshots = sortedJobs().map(snapshot(for:))
    for continuation in updateContinuations.values { continuation.yield(snapshots) }
  }

  func commit(_ job: PersistedDownload) throws {
    let previous = jobs[job.id]
    jobs[job.id] = job
    do { try persist() } catch {
      jobs[job.id] = previous
      throw error
    }
  }

  func commitRemoval(_ id: UUID) throws {
    guard let previous = jobs.removeValue(forKey: id) else {
      throw DownloadCoordinatorError.missingJob(id)
    }
    do { try persist() } catch {
      jobs[id] = previous
      throw error
    }
  }

  func snapshot(for job: PersistedDownload) -> DownloadSnapshot {
    let current = job.snapshot
    guard let persistenceError else { return current }
    return DownloadSnapshot(
      id: current.id,
      request: current.request,
      state: current.state,
      progress: current.progress,
      bytesReceived: current.bytesReceived,
      destinationDirectory: current.destinationDirectory,
      destinationURL: current.destinationURL,
      packageVerified: current.packageVerified,
      compatibilityPatchDestinationURL: current.compatibilityPatchDestinationURL,
      compatibilityPatchVerified: current.compatibilityPatchVerified,
      extractedDirectoryURL: current.extractedDirectoryURL,
      legacyOutputLocationUnknown: current.legacyOutputLocationUnknown,
      errorMessage: LocalizedMessage("error.download.queueSaveFailed", .text(persistenceError))
        .resolved(),
      canResume: current.canResume,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt
    )
  }

  func isPersistenceFailure(_ error: Error) -> Bool {
    guard let error = error as? DownloadCoordinatorError, case .persistenceFailure = error else {
      return false
    }
    return true
  }

  func sortedJobs() -> [PersistedDownload] { jobs.values.sorted { $0.createdAt > $1.createdAt } }
}
