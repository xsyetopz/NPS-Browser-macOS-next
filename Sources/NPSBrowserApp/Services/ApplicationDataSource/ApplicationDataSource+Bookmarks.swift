import Foundation
import NPSCore

extension ApplicationDataSource {
  func loadBookmarkedIDs() async throws -> Set<String> {
    Set(try await catalogue.bookmarks().map(\.id))
  }

  func loadBookmarksForExport() async throws -> [Bookmark] { try await catalogue.bookmarks() }

  func setBookmarked(_ entry: BrowserEntry, isBookmarked: Bool) async throws {
    guard let item = try await catalogue.allItems().first(where: { $0.id == entry.id }) else {
      throw CatalogueRefreshError.itemUnavailable(.text(entry.titleID))
    }
    try await catalogue.setBookmarked(item, isBookmarked: isBookmarked)
  }
}
