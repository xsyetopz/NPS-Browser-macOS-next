import Foundation

public struct Bookmark: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let titleID: String?
  public let downloadURL: URL?
  public let name: String?
  public let fileType: String?
  public let consoleType: String?
  public let zrif: String?

  public init(
    id: String,
    titleID: String?,
    downloadURL: URL?,
    name: String?,
    fileType: String?,
    consoleType: String?,
    zrif: String?
  ) {
    self.id = id
    self.titleID = titleID
    self.downloadURL = downloadURL
    self.name = name
    self.fileType = fileType
    self.consoleType = consoleType
    self.zrif = zrif
  }

  public init(item: CatalogItem) {
    self.init(
      id: item.id,
      titleID: item.titleID,
      downloadURL: item.packageURL,
      name: item.name,
      fileType: item.fileType.rawValue,
      consoleType: item.consoleType.rawValue,
      zrif: item.zrif
    )
  }

  /// Serializes bookmarks as RFC 4180-style CSV with a stable header and escaped cells.
  public static func csv(_ bookmarks: [Self]) -> String {
    let header = ["uuid", "titleId", "downloadUrl", "name", "fileType", "consoleType", "zrif"]
    let rows = bookmarks.map { bookmark in
      [
        bookmark.id, bookmark.titleID ?? "", bookmark.downloadURL?.absoluteString ?? "",
        bookmark.name ?? "", bookmark.fileType ?? "", bookmark.consoleType ?? "",
        bookmark.zrif ?? "",
      ]
    }
    return ([header] + rows).map { $0.map(csvCell).joined(separator: ",") }.joined(
      separator: "\r\n"
    ) + "\r\n"
  }
}

private func csvCell(_ value: String) -> String {
  guard value.contains(",") || value.contains("\"") || value.contains("\r") || value.contains("\n")
  else { return value }
  return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}
