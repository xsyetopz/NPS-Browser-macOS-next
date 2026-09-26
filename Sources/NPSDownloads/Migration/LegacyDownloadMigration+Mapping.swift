import Foundation

extension LegacyDownloadMigration {
  static func sameLegacyDownload(_ lhs: PersistedDownload, _ rhs: PersistedDownload) -> Bool {
    lhs.request == rhs.request
      && lhs.destinationURL?.standardizedFileURL == rhs.destinationURL?.standardizedFileURL
  }

  static func archivedPSVOutputDirectory(
    consoleType: String,
    fileType: String,
    titleID: String?,
    destinationURL: URL?
  ) -> URL? {
    guard consoleType.caseInsensitiveCompare("PSV") == .orderedSame, let titleID,
      titleID.range(of: #"^[A-Za-z0-9]{4,16}$"#, options: .regularExpression) != nil,
      let destinationURL, destinationURL.isFileURL
    else { return nil }

    let outputFolder: String
    switch fileType.lowercased() {
    case "game": outputFolder = "app"
    case "dlc": outputFolder = "addcont"
    case "update": outputFolder = "patch"
    default: return nil
    }

    let consoleDirectory = destinationURL.deletingLastPathComponent()
    guard consoleDirectory.lastPathComponent.caseInsensitiveCompare("PSV") == .orderedSame else {
      return nil
    }
    return consoleDirectory.appendingPathComponent(outputFolder, isDirectory: true)
      .appendingPathComponent(titleID, isDirectory: true)
  }

  static func isDirectory(at url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  static func extensionFor(fileType: String, sourceURL: URL) -> String {
    switch fileType.lowercased() {
    case "cpack", "cpatch": return "ppk"
    case "rap": return "rap"
    default:
      let pathExtension = sourceURL.pathExtension.lowercased()
      return ["pkg", "ppk", "rap"].contains(pathExtension) ? pathExtension : "pkg"
    }
  }

  static func normalizedProgress(_ value: Double?) -> Double {
    guard let value, value.isFinite else { return 0 }
    return min(1, max(0, value / 100))
  }

  static func nextAvailableURL(
    title: String,
    fileExtension: String,
    in directory: URL,
    occupiedPaths: inout Set<String>
  ) -> URL {
    CollisionFreeFileURL.next(
      title: title,
      fileExtension: fileExtension,
      lowercasingExtension: false,
      in: directory,
      occupiedPaths: occupiedPaths
    )
  }
}
