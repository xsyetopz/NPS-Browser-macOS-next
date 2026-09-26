import Foundation

struct CatalogEmptyState: Equatable {
  let titleKey: String
  let messageKey: String

  static func forFilter(section: BrowserSection, query: String) -> Self {
    guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return Self(titleKey: "empty.search.title", messageKey: "empty.search.message")
    }
    if section == .bookmarks {
      return Self(titleKey: "empty.bookmarks.title", messageKey: "empty.bookmarks.message")
    }
    return Self(titleKey: "empty.catalog.title", messageKey: "empty.catalog.message")
  }
}
