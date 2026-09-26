import Foundation
import NPSBrowserAppResources

/// Job titles shared by the queued placeholder rows and the requests they stand for.
enum DownloadTitle {
  static func update(for entry: BrowserEntry) -> String {
    String(format: AppResources.localized("downloads.title.update"), entry.title)
  }

  static func rap(for entry: BrowserEntry) -> String {
    String(format: AppResources.localized("downloads.title.rap"), entry.title, entry.titleID)
  }

  /// File-name title for an update package, the same in every UI language.
  static func updateFileTitle(for entry: BrowserEntry) -> String { "\(entry.title) Update" }

  /// File-name title for a RAP file, the same in every UI language.
  static func rapFileTitle(for entry: BrowserEntry) -> String {
    "\(entry.title) RAP \(entry.titleID)"
  }
}
