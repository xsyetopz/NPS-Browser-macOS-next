import Foundation
import NPSCore

struct BrowserEntry: Identifiable, Hashable, Sendable {
  var id: String
  var title: String
  var titleID: String
  var console: String
  var consoleCode: String = ""
  var category: String
  var region: String
  var fileSize: Int64?
  var packageURL: URL?
  var rapDownloadURL: URL?
  var sha256: String?
  var contentID: String?
  var isCompatibilityPack: Bool = false
  var compatibilityPackKind: CompatibilityPackKind?
  var compatibilityPatchURL: URL?
  var matchingPackURL: URL?
  var matchingPackTitle: String?

  var supportsUpdateDownload: Bool {
    consoleCode == ConsoleType.PSV.rawValue && category == FileType.Game.rawValue && titleID != "—"
      && !titleID.isEmpty
  }

  var supportsPackageDownload: Bool { Self.isUsableDownloadURL(packageURL) }

  var supportsRAPDownload: Bool {
    guard consoleCode == ConsoleType.PS3.rawValue,
      titleID.range(of: #"^[A-Za-z0-9]{4,16}$"#, options: .regularExpression) != nil
    else { return false }
    return Self.isUsableDownloadURL(rapDownloadURL)
  }

  private static func isUsableDownloadURL(_ url: URL?) -> Bool {
    guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
    else { return false }
    return true
  }
}
