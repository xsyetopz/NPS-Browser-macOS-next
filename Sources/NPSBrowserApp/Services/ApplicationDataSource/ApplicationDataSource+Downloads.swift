import Foundation
import NPSCore
import NPSDownloads

extension ApplicationDataSource {
  func loadDownloads() async throws -> [DownloadEntry] {
    await downloads.snapshots().map(Self.downloadEntry)
  }

  func observeDownloads() async -> AsyncStream<[DownloadEntry]> {
    let snapshots = await downloads.updates()
    return AsyncStream { continuation in
      let task = Task {
        for await values in snapshots { continuation.yield(values.map(Self.downloadEntry)) }
        continuation.finish()
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }

  func completedFileURL(for downloadID: String) async throws -> URL {
    guard let id = UUID(uuidString: downloadID), let url = await downloads.revealURL(for: id) else {
      throw DownloadCoordinatorError.downloadUnavailable(
        LocalizedMessage("error.reveal.missingFile")
      )
    }
    return url
  }

  func controlDownload(_ downloadID: String, action: DownloadAction) async throws {
    guard let id = UUID(uuidString: downloadID) else {
      throw DownloadCoordinatorError.downloadUnavailable(
        LocalizedMessage("error.reveal.invalidIdentifier")
      )
    }
    switch action {
    case .pause: try await downloads.pause(id)
    case .resume: try await downloads.resume(id)
    case .restart: try await downloads.restart(id)
    case .retryExtraction: try await downloads.retryExtraction(id)
    case .remove: try await downloads.remove(id)
    case .reveal:
      throw DownloadCoordinatorError.downloadUnavailable(LocalizedMessage("error.reveal.useReveal"))
    }
  }

  func pauseDownloads() async throws { try await downloads.pauseAll() }
}
