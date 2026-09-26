import Foundation
import NPSBrowserAppResources
import NPSCore
import NPSDownloads

extension ApplicationDataSource {
  static func compatibilityEntries(from compatibilityPacks: [CompatibilityPack]) -> [BrowserEntry] {
    let patchURLs = Dictionary(
      grouping: compatibilityPacks.filter { $0.kind == .patch },
      by: \.titleID
    )
    let packURLs = Dictionary(
      grouping: compatibilityPacks.filter { $0.kind == .pack },
      by: \.titleID
    )
    return compatibilityPacks.map { pack in
      switch pack.kind {
      case .pack:
        return BrowserEntry(
          compatibilityPack: pack,
          matchingPatchURL: patchURLs[pack.titleID]?.first?.downloadURL
        )
      case .patch:
        let matchingPack = packURLs[pack.titleID]?.first
        return BrowserEntry(
          compatibilityPack: pack,
          matchingPatchURL: nil,
          matchingPackURL: matchingPack?.downloadURL,
          matchingPackTitle: matchingPack?.displayName ?? matchingPack?.titleID
        )
      }
    }
  }

  static func downloadEntry(_ snapshot: DownloadSnapshot) -> DownloadEntry {
    let progress: Double? =
      if snapshot.state == .complete {
        1
      } else if snapshot.state == .downloading, snapshot.progress == 0 {
        // The snapshot has no expected response-length field. Fall back to
        // the catalogue size when available; otherwise don't expose zero
        // as a misleading determinate percentage for an active transfer.
        if let expectedByteCount = snapshot.request.expectedByteCount, expectedByteCount > 0 {
          min(0.99, max(0, Double(snapshot.bytesReceived) / Double(expectedByteCount)))
        } else {
          nil
        }
      } else { snapshot.progress }
    let detail =
      snapshot.errorMessage
      ?? String(
        format: AppResources.localized("downloads.detail.format"),
        snapshot.request.titleID ?? "",
        ByteCountFormatter.string(fromByteCount: snapshot.bytesReceived, countStyle: .file)
      )
    return DownloadEntry(
      id: snapshot.id.uuidString,
      title: snapshot.request.title,
      detail: detail,
      state: snapshot.state,
      progress: progress,
      completedFile: snapshot.completedURL,
      titleID: snapshot.request.titleID,
      createdAt: snapshot.createdAt,
      canPause: snapshot.state == .downloading || snapshot.state == .queued,
      canResume: snapshot.state == .paused && snapshot.canResume,
      canRestart: snapshot.canRestart,
      canRetryExtraction: snapshot.state == .failed && snapshot.hasVerifiedPackage
        && snapshot.request.extractAfterDownload,
      canRemove: snapshot.state != .extracting
    )
  }
}
