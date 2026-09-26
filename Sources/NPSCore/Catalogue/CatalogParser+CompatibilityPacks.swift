import Foundation

extension CatalogParser {
  /// Parses the repository's relative package path and display name feed format.
  public static func parseCompatibilityPacks(
    _ input: String,
    kind: CompatibilityPackKind
  ) throws -> [CompatibilityPack] {
    let normalized = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\r",
      with: "\n"
    )
    guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CatalogParseError.emptyInput
    }

    var packs: [CompatibilityPack] = []
    for (offset, rawLine) in normalized.components(separatedBy: "\n").enumerated() {
      let row = offset + 1
      guard !rawLine.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
      guard let separator = rawLine.firstIndex(of: "=") else {
        throw CatalogParseError.invalidCompatibilityEntry(row: row, reason: .missingSeparator)
      }

      let rawPath = String(rawLine[..<separator])
      let displayName = String(rawLine[rawLine.index(after: separator)...]).trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard !rawPath.isEmpty, rawPath == rawPath.trimmingCharacters(in: .whitespacesAndNewlines),
        !displayName.isEmpty
      else {
        throw CatalogParseError.invalidCompatibilityEntry(row: row, reason: .missingPathOrName)
      }

      let pathComponents = rawPath.split(separator: "/", omittingEmptySubsequences: false).map(
        String.init
      )
      let titleIDIndex: Int
      switch kind {
      case .pack:
        guard pathComponents.count == 2 else {
          throw CatalogParseError.invalidCompatibilityEntry(row: row, reason: .invalidPackPath)
        }
        titleIDIndex = 0
      case .patch:
        guard pathComponents.count == 3, pathComponents[0] == "patch" else {
          throw CatalogParseError.invalidCompatibilityEntry(row: row, reason: .invalidPatchPath)
        }
        titleIDIndex = 1
      }

      guard pathComponents.allSatisfy(isSafeCompatibilityPathComponent) else {
        throw CatalogParseError.invalidCompatibilityEntry(row: row, reason: .unsafePath)
      }
      let titleID = pathComponents[titleIDIndex].uppercased()
      guard isValidTitleID(titleID) else {
        throw CatalogParseError.invalidCompatibilityEntry(row: row, reason: .invalidTitleID)
      }
      guard pathComponents.last?.lowercased().hasSuffix(".ppk") == true else {
        throw CatalogParseError.invalidCompatibilityEntry(row: row, reason: .invalidExtension)
      }

      guard let url = compatibilityURL(pathComponents) else {
        throw CatalogParseError.invalidCompatibilityEntry(row: row, reason: .invalidURL)
      }
      packs.append(
        CompatibilityPack(titleID: titleID, downloadURL: url, kind: kind, displayName: displayName)
      )
    }
    return packs
  }

  private static func isSafeCompatibilityPathComponent(_ component: String) -> Bool {
    guard !component.isEmpty, component != ".", component != ".." else { return false }
    return component.unicodeScalars.allSatisfy { scalar in
      scalar.isASCII
        && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
          || scalar == ".")
    }
  }

  private static func compatibilityURL(_ pathComponents: [String]) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "gitlab.com"
    components.percentEncodedPath =
      "/nopaystation_repos/nps_compati_packs/raw/master/" + pathComponents.joined(separator: "/")
    return components.url
  }
}
