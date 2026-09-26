import Foundation

extension CatalogParser {
  static func parse(_ values: [String], kind: CatalogKind, row: Int) throws -> CatalogItem {
    func value(_ index: Int) -> String {
      values[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func optional(_ index: Int) -> String? {
      let result = value(index)
      let missingMarkers = ["N/A", "MISSING", "CART ONLY", "NOT REQUIRED", "UNLOCK/LICENSE BY DLC"]
      guard !result.isEmpty, !missingMarkers.contains(result.uppercased()) else { return nil }
      return result
    }

    func url(_ rawValue: String?, field: String) throws -> URL? {
      guard let rawValue else { return nil }
      guard let parsed = URL(string: rawValue), isHTTPURL(parsed) else {
        throw CatalogParseError.invalidField(row: row, field: field, value: rawValue)
      }
      return parsed
    }

    func parsedDate(_ index: Int) throws -> Date? {
      guard let raw = optional(index) else { return nil }
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = .current
      formatter.isLenient = false
      formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
      guard let date = formatter.date(from: raw) else {
        throw CatalogParseError.invalidField(row: row, field: "lastModificationDate", value: raw)
      }
      return date
    }

    func parsedSize(_ index: Int) throws -> Int64? {
      guard let raw = optional(index) else { return nil }
      guard let result = Int64(raw) else {
        // Some upstream PS3 rows use a fractional, unitless display value
        // (for example `4.7`). It cannot safely become a byte count.
        if let displayValue = Double(raw), displayValue.isFinite, displayValue >= 0 { return nil }
        throw CatalogParseError.invalidField(row: row, field: "fileSize", value: raw)
      }
      guard result >= 0 else {
        throw CatalogParseError.invalidField(row: row, field: "fileSize", value: raw)
      }
      return result
    }

    func parsedHash(_ index: Int) throws -> String? {
      guard let raw = optional(index) else { return nil }
      guard raw.count == 64,
        raw.utf8.allSatisfy({ byte in
          (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
        })
      else { throw CatalogParseError.invalidField(row: row, field: "sha256", value: raw) }
      return raw.lowercased()
    }

    let titleID = optional(0) ?? ""
    let region = optional(1)
    let nameIndex: Int
    let packageIndex: Int
    let contentIndex: Int
    let dateIndex: Int
    let originalNameIndex: Int?
    let sizeIndex: Int
    let hashIndex: Int
    let zrifIndex: Int?
    let firmwareIndex: Int?
    let rapIndex: Int?
    let rapURLIndex: Int?

    switch (kind.console, kind.fileType) {
    case (.PSV, .Game):
      nameIndex = 2
      packageIndex = 3
      zrifIndex = 4
      contentIndex = 5
      dateIndex = 6
      originalNameIndex = 7
      sizeIndex = 8
      hashIndex = 9
      firmwareIndex = 10
      rapIndex = nil
      rapURLIndex = nil
    case (.PSV, .DLC), (.PSV, .Theme):
      nameIndex = 2
      packageIndex = 3
      zrifIndex = 4
      contentIndex = 5
      dateIndex = 6
      originalNameIndex = nil
      sizeIndex = 7
      hashIndex = 8
      firmwareIndex = nil
      rapIndex = nil
      rapURLIndex = nil
    case (.PS3, .Game), (.PS3, .DLC), (.PS3, .Theme), (.PS3, .Avatar):
      nameIndex = 2
      packageIndex = 3
      zrifIndex = nil
      rapIndex = 4
      contentIndex = 5
      dateIndex = 6
      originalNameIndex = nil
      sizeIndex = 8
      hashIndex = 9
      firmwareIndex = nil
      rapURLIndex = nil
    case (.PSP, .Game):
      nameIndex = 3
      packageIndex = 4
      contentIndex = 5
      dateIndex = 6
      rapIndex = 7
      rapURLIndex = 8
      sizeIndex = 9
      hashIndex = 10
      originalNameIndex = nil
      zrifIndex = nil
      firmwareIndex = nil
    case (.PSP, .DLC):
      nameIndex = 2
      packageIndex = 3
      contentIndex = 4
      dateIndex = 5
      rapIndex = 6
      rapURLIndex = 7
      sizeIndex = 8
      hashIndex = 9
      originalNameIndex = nil
      zrifIndex = nil
      firmwareIndex = nil
    case (.PSM, .Game):
      nameIndex = 2
      packageIndex = 3
      zrifIndex = 4
      contentIndex = 5
      dateIndex = 6
      originalNameIndex = nil
      sizeIndex = 7
      hashIndex = 8
      firmwareIndex = nil
      rapIndex = nil
      rapURLIndex = nil
    case (.PSX, .Game):
      nameIndex = 2
      packageIndex = 3
      contentIndex = 4
      dateIndex = 5
      originalNameIndex = 6
      sizeIndex = 7
      hashIndex = 8
      zrifIndex = nil
      firmwareIndex = nil
      rapIndex = nil
      rapURLIndex = nil
    default: throw CatalogParseError.unsupportedKind(kind)
    }

    let name = optional(nameIndex) ?? ""
    let packageURL = try url(optional(packageIndex), field: "pkgDirectLink")
    let contentID = contentIndex < values.count ? optional(contentIndex) : nil
    guard !titleID.isEmpty || !name.isEmpty || contentID != nil || packageURL != nil else {
      throw CatalogParseError.missingIdentity(row: row)
    }
    let date = try parsedDate(dateIndex)
    let originalName = originalNameIndex.flatMap(optional)
    let fileSize = try parsedSize(sizeIndex)
    let sha256 = try parsedHash(hashIndex)
    let zrif = zrifIndex.flatMap(optional)
    let rap = rapIndex.flatMap(optional)
    let rapURL: URL?
    if let rapURLIndex {
      rapURL = try url(optional(rapURLIndex), field: "rapDownloadFile")
    } else if kind.console == .PS3, let rap, let contentID {
      rapURL = Self.rapURL(contentID: contentID, rap: rap)
    } else {
      rapURL = nil
    }

    let firmware: Float?
    if let firmwareIndex, let raw = optional(firmwareIndex) {
      guard let parsed = Float(raw), parsed.isFinite, parsed >= 0 else {
        throw CatalogParseError.invalidField(row: row, field: "requiredFw", value: raw)
      }
      firmware = parsed
    } else {
      firmware = nil
    }

    return CatalogItem(
      titleID: titleID,
      region: region,
      contentID: contentID,
      name: name,
      packageURL: packageURL,
      lastModified: date,
      fileSize: fileSize,
      sha256: sha256,
      zrif: zrif,
      originalName: originalName,
      requiredFirmware: firmware,
      rap: rap,
      rapDownloadURL: rapURL,
      consoleType: kind.console,
      fileType: kind.fileType
    )
  }

  private static func rapURL(contentID: String, rap: String) -> URL? {
    var components = URLComponents(string: "https://nopaystation.com/tools/rap2file")
    let pathComponents = [contentID, rap].map { component in
      let allowedPathComponentCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
      )
      return component.addingPercentEncoding(withAllowedCharacters: allowedPathComponentCharacters)
        ?? component
    }
    if let path = components?.percentEncodedPath {
      components?.percentEncodedPath = path + "/" + pathComponents.joined(separator: "/")
    }
    guard let url = components?.url, isHTTPURL(url) else { return nil }
    return url
  }

  private static func isHTTPURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
    else { return false }
    return true
  }
}
