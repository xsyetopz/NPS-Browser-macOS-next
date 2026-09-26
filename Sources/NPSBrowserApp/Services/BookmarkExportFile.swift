import Foundation
import NPSCore

enum BookmarkExportFile {
  static func write(_ bookmarks: [Bookmark], to url: URL) throws {
    try Data(Bookmark.csv(bookmarks).utf8).write(to: url, options: .atomic)
  }
}
