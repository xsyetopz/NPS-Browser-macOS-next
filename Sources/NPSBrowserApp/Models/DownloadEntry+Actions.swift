import Foundation

extension DownloadEntry {
  var availableActions: [DownloadAction] {
    var actions: [DownloadAction] = []
    if canPause { actions.append(.pause) }
    if canResume { actions.append(.resume) }
    if canRetryExtraction { actions.append(.retryExtraction) }
    if canRestart { actions.append(.restart) }
    if completedFile != nil { actions.append(.reveal) }
    if canRemove { actions.append(.remove) }
    return actions
  }

  func canPerform(_ action: DownloadAction) -> Bool { availableActions.contains(action) }
}
