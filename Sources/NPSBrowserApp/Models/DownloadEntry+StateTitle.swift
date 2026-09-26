import Foundation
import NPSBrowserAppResources

extension DownloadEntry {
  var stateTitleKey: String { "downloads.state.\(state.rawValue)" }

  var stateTitle: String { statusText ?? AppResources.localized(stateTitleKey) }
}
