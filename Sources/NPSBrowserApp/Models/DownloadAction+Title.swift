import Foundation
import NPSBrowserAppResources

extension DownloadAction {
  var titleKey: String {
    switch self {
    case .pause: "action.pause"
    case .resume: "action.resume"
    case .restart: "action.restart"
    case .retryExtraction: "action.retryExtraction"
    case .remove: "action.remove"
    case .reveal: "action.reveal"
    }
  }

  var title: String { AppResources.localized(titleKey) }
}
