import Foundation

extension FileType {
  /// The content type's name as a catalog key, shared with the sidebar section titles.
  public var localizedTitleMessage: LocalizedMessage {
    switch self {
    case .Game: LocalizedMessage("section.games")
    case .Update: LocalizedMessage("section.updates")
    case .DLC: LocalizedMessage("section.dlc")
    case .Theme: LocalizedMessage("section.themes")
    case .Avatar: LocalizedMessage("section.avatars")
    case .CPack: LocalizedMessage("section.compatPacks")
    case .CPatch: LocalizedMessage("section.compatPatches")
    case .RAP: LocalizedMessage("fileType.rap")
    }
  }
}
