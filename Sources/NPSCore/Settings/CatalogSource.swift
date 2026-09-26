import Foundation

public enum CatalogSource: String, CaseIterable, Codable, Hashable, Sendable {
  case psvGames = "src_psv_games"
  case psvDLCs = "src_psv_dlcs"
  case psvThemes = "src_psv_themes"
  case pspGames = "src_psp_games"
  case pspDLCs = "src_psp_dlcs"
  case psmGames = "src_psm_games"
  case psxGames = "src_psx_games"
  case ps3Games = "src_ps3_games"
  case ps3DLCs = "src_ps3_dlcs"
  case ps3Themes = "src_ps3_themes"
  case ps3Avatars = "src_ps3_avatars"
  case compatPacks = "src_compatPacks"
  case compatPatch = "src_compatPatch"

  public var defaultURL: URL {
    switch self {
    case .psvGames: URL(string: "https://nopaystation.com/tsv/PSV_GAMES.tsv")!
    case .psvDLCs: URL(string: "https://nopaystation.com/tsv/PSV_DLCS.tsv")!
    case .psvThemes: URL(string: "https://nopaystation.com/tsv/PSV_THEMES.tsv")!
    case .pspGames: URL(string: "https://nopaystation.com/tsv/PSP_GAMES.tsv")!
    case .pspDLCs: URL(string: "https://nopaystation.com/tsv/PSP_DLCS.tsv")!
    case .psmGames: URL(string: "https://nopaystation.com/tsv/PSM_GAMES.tsv")!
    case .psxGames: URL(string: "https://nopaystation.com/tsv/PSX_GAMES.tsv")!
    case .ps3Games: URL(string: "https://nopaystation.com/tsv/PS3_GAMES.tsv")!
    case .ps3DLCs: URL(string: "https://nopaystation.com/tsv/PS3_DLCS.tsv")!
    case .ps3Themes: URL(string: "https://nopaystation.com/tsv/PS3_THEMES.tsv")!
    case .ps3Avatars: URL(string: "https://nopaystation.com/tsv/PS3_AVATARS.tsv")!
    case .compatPacks:
      URL(string: "https://gitlab.com/nopaystation_repos/nps_compati_packs/raw/master/entries.txt")!
    case .compatPatch:
      URL(
        string:
          "https://gitlab.com/nopaystation_repos/nps_compati_packs/raw/master/entries_patch.txt"
      )!
    }
  }
}
