import Foundation

/// A value-only catalogue entry. It can safely cross actor boundaries.
public struct CatalogItem: Codable, Equatable, Identifiable, Sendable {
  public let titleID: String
  public let region: String?
  public let contentID: String?
  public let name: String
  public let packageURL: URL?
  public let lastModified: Date?
  public let fileSize: Int64?
  public let sha256: String?
  public let zrif: String?
  public let originalName: String?
  public let requiredFirmware: Float?
  public let rap: String?
  public let rapDownloadURL: URL?
  public let consoleType: ConsoleType
  public let fileType: FileType

  public var id: String {
    guard titleID.isEmpty, contentID?.isEmpty != false else { return legacyPrimaryKey }
    let fallbackIdentity = [region ?? "", name, packageURL?.absoluteString ?? ""].joined(
      separator: "\u{1F}"
    )
    return "\(legacyPrimaryKey)#\(fallbackIdentity)"
  }

  /// Matches the stable key used by legacy bookmarks and the old catalogue.
  public var legacyPrimaryKey: String {
    "\(region ?? "")\(fileType.rawValue)\(titleID)\(contentID ?? "")"
  }

  public init(
    titleID: String,
    region: String? = nil,
    contentID: String? = nil,
    name: String,
    packageURL: URL? = nil,
    lastModified: Date? = nil,
    fileSize: Int64? = nil,
    sha256: String? = nil,
    zrif: String? = nil,
    originalName: String? = nil,
    requiredFirmware: Float? = nil,
    rap: String? = nil,
    rapDownloadURL: URL? = nil,
    consoleType: ConsoleType,
    fileType: FileType
  ) {
    self.titleID = titleID
    self.region = region
    self.contentID = contentID
    self.name = name
    self.packageURL = packageURL
    self.lastModified = lastModified
    self.fileSize = fileSize
    self.sha256 = sha256
    self.zrif = zrif
    self.originalName = originalName
    self.requiredFirmware = requiredFirmware
    self.rap = rap
    self.rapDownloadURL = rapDownloadURL
    self.consoleType = consoleType
    self.fileType = fileType
  }

  /// Returns a safe leaf name. Collision handling belongs to the destination owner.
  public func safeFilename(extension fileExtension: String = "pkg") -> String {
    let cleanedName = safeLeafComponent(name)
    let fallbackTitleID = safeLeafComponent(titleID)
    let fallbackURLName = safeLeafComponent(
      packageURL?.deletingPathExtension().lastPathComponent ?? ""
    )
    let baseName =
      [cleanedName, fallbackTitleID, fallbackURLName].first { !$0.isEmpty } ?? "download"
    let cleanedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
      .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    guard !cleanedExtension.isEmpty else { return baseName }
    return "\(baseName).\(cleanedExtension)"
  }
}

private func safeLeafComponent(_ source: String) -> String {
  var leaf = String.UnicodeScalarView()
  var replacingInvalidRun = false
  for scalar in source.precomposedStringWithCanonicalMapping.unicodeScalars {
    let isForbidden =
      CharacterSet.controlCharacters.contains(scalar) || scalar == "/" || scalar == "\\"
      || scalar == ":"
    if isForbidden {
      if !replacingInvalidRun, let hyphen = "-".unicodeScalars.first { leaf.append(hyphen) }
      replacingInvalidRun = true
    } else {
      leaf.append(scalar)
      replacingInvalidRun = false
    }
  }
  return String(leaf).trimmingCharacters(
    in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-"))
  )
}
