import Foundation
import NPSCore

extension DownloadState {
  /// The state's name as a catalog key (`downloads.state.<rawValue>`).
  public var localizedTitleMessage: LocalizedMessage {
    LocalizedMessage("downloads.state.\(rawValue)")
  }
}
