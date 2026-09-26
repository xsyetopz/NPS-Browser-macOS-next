import Foundation

enum BrowserSection: String, CaseIterable, Sendable {
  case allItems
  case ps3
  case psVita
  case psm
  case psp
  case psx
  case games
  case updates
  case dlc
  case themes
  case avatars
  case compatPacks
  case compatPatches
  case bookmarks
  case downloads

  var titleKey: String {
    switch self {
    case .allItems: "section.all"
    case .ps3: "section.ps3"
    case .psVita: "section.psvita"
    case .psm: "section.psm"
    case .psp: "section.psp"
    case .psx: "section.psx"
    case .games: "section.games"
    case .updates: "section.updates"
    case .dlc: "section.dlc"
    case .themes: "section.themes"
    case .avatars: "section.avatars"
    case .compatPacks: "section.compatPacks"
    case .compatPatches: "section.compatPatches"
    case .bookmarks: "section.bookmarks"
    case .downloads: "section.downloads"
    }
  }

  var navigationTitleKey: String {
    switch self {
    case .psVita: "section.nav.psvita"
    case .psp: "section.nav.psp"
    case .psx: "section.nav.psx"
    case .compatPacks: "section.nav.compatPacks"
    case .compatPatches: "section.nav.compatPatches"
    default: titleKey
    }
  }

  var symbolName: String {
    switch self {
    case .allItems: "square.grid.2x2"
    case .ps3: "gamecontroller"
    case .psVita: "gamecontroller"
    case .psm: "gamecontroller"
    case .psp: "gamecontroller"
    case .psx: "gamecontroller"
    case .games: "square.grid.2x2"
    case .updates: "arrow.down.app"
    case .dlc: "puzzlepiece"
    case .themes: "paintbrush"
    case .avatars: "person.crop.square"
    case .compatPacks: "shippingbox"
    case .compatPatches: "shippingbox.fill"
    case .bookmarks: "star"
    case .downloads: "arrow.down.circle"
    }
  }
}
