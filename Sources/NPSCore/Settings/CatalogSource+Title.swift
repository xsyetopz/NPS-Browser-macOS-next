import Foundation

extension CatalogSource {
  /// The source's name in the current UI language.
  public var localizedTitle: String { localizedTitleMessage.resolved() }

  /// The source's name as a catalog key, for messages rendered later.
  public var localizedTitleMessage: LocalizedMessage {
    switch self {
    case .psvGames: LocalizedMessage("source.psvGames")
    case .psvDLCs: LocalizedMessage("source.psvDLCs")
    case .psvThemes: LocalizedMessage("source.psvThemes")
    case .pspGames: LocalizedMessage("source.pspGames")
    case .pspDLCs: LocalizedMessage("source.pspDLCs")
    case .psmGames: LocalizedMessage("source.psmGames")
    case .psxGames: LocalizedMessage("source.psxGames")
    case .ps3Games: LocalizedMessage("source.ps3Games")
    case .ps3DLCs: LocalizedMessage("source.ps3DLCs")
    case .ps3Themes: LocalizedMessage("source.ps3Themes")
    case .ps3Avatars: LocalizedMessage("source.ps3Avatars")
    case .compatPacks: LocalizedMessage("source.compatPacks")
    case .compatPatch: LocalizedMessage("source.compatPatch")
    }
  }
}
