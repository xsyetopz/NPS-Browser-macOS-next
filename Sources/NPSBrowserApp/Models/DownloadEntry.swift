import Foundation
import NPSDownloads

struct DownloadEntry: Identifiable, Hashable, Sendable {
  var id: String
  var title: String
  var detail: String
  var state: DownloadState
  var statusText: String?
  var progress: Double?
  var completedFile: URL?
  var titleID: String?
  var createdAt: Date?
  var canPause: Bool = false
  var canResume: Bool = false
  var canRestart: Bool = false
  var canRetryExtraction: Bool = false
  var canRemove: Bool = true

  var requiresRemovalConfirmation: Bool {
    state == .queued || state == .downloading || state == .paused || state == .verifying
  }
}
