import Foundation
import NPSCore

enum CatalogFilter {
  static func matching(
    _ entries: [BrowserEntry],
    section: BrowserSection,
    bookmarkedIDs: Set<String>,
    query: String,
    hideInvalidURLItems: Bool = true
  ) -> [BrowserEntry] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: .current
    )
    return entries.filter { entry in
      switch section {
      case .allItems: break
      case .ps3 where !entry.console.localizedCaseInsensitiveContains("PS3"): return false
      case .psVita where !entry.console.localizedCaseInsensitiveContains("Vita"): return false
      case .psm where entry.consoleCode != ConsoleType.PSM.rawValue: return false
      case .psp where !entry.console.localizedCaseInsensitiveContains("PSP"): return false
      case .psx
      where !entry.console.localizedCaseInsensitiveContains("PSX")
        && !entry.console.localizedCaseInsensitiveContains("PS1"):
        return false
      case .games where !entry.category.localizedCaseInsensitiveContains("Game"): return false
      case .updates where !entry.supportsUpdateDownload: return false
      case .dlc where !entry.category.localizedCaseInsensitiveContains("DLC"): return false
      case .themes where !entry.category.localizedCaseInsensitiveContains("Theme"): return false
      case .avatars where !entry.category.localizedCaseInsensitiveContains("Avatar"): return false
      case .compatPacks where !entry.category.localizedCaseInsensitiveContains("CPack"):
        return false
      case .compatPatches where !entry.category.localizedCaseInsensitiveContains("CPatch"):
        return false
      case .bookmarks where !bookmarkedIDs.contains(entry.id): return false
      case .downloads: return false
      default: break
      }
      guard !hideInvalidURLItems || entry.packageURL != nil || entry.supportsRAPDownload else {
        return false
      }
      guard !needle.isEmpty else { return true }
      let searchable = [entry.title, entry.titleID, entry.console, entry.category, entry.region]
        .joined(separator: " ").folding(
          options: [.caseInsensitive, .diacriticInsensitive],
          locale: .current
        )
      return searchable.contains(needle)
    }
  }
}
