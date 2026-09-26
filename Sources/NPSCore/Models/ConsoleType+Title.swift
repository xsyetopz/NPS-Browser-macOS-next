import Foundation

extension ConsoleType {
  /// The console's name as a catalog key, shared with the sidebar section titles.
  public var localizedTitleMessage: LocalizedMessage {
    switch self {
    case .PSV: LocalizedMessage("section.psvita")
    case .PS3: LocalizedMessage("section.ps3")
    case .PSP: LocalizedMessage("section.psp")
    case .PSM: LocalizedMessage("section.psm")
    case .PSX: LocalizedMessage("section.psx")
    }
  }
}
