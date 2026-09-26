import Foundation

public enum CatalogParser {
  /// Parses the published NPS TSV layouts without assuming every row has all optional values.
  public static func parseTSV(_ input: String, kind: CatalogKind) throws -> [CatalogItem] {
    let normalized = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\r",
      with: "\n"
    )
    let lines = normalized.components(separatedBy: "\n")
    guard
      let firstNonEmpty = lines.firstIndex(where: {
        !$0.trimmingCharacters(in: .whitespaces).isEmpty
      })
    else { throw CatalogParseError.emptyInput }
    guard firstNonEmpty < lines.count else { throw CatalogParseError.missingHeader }

    let header = lines[firstNonEmpty].trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\u{FEFF}", with: "")
    guard !header.isEmpty else { throw CatalogParseError.missingHeader }

    let expectedHeader: [String]
    switch (kind.console, kind.fileType) {
    case (.PSV, .Game):
      expectedHeader = [
        "Title ID", "Region", "Name", "PKG direct link", "zRIF", "Content ID",
        "Last Modification Date", "Original Name", "File Size", "SHA256", "Required FW",
      ]
    case (.PSV, .DLC), (.PSV, .Theme):
      expectedHeader = [
        "Title ID", "Region", "Name", "PKG direct link", "zRIF", "Content ID",
        "Last Modification Date", "File Size", "SHA256",
      ]
    case (.PS3, .Game), (.PS3, .DLC), (.PS3, .Theme), (.PS3, .Avatar):
      expectedHeader = [
        "Title ID", "Region", "Name", "PKG direct link", "RAP", "Content ID",
        "Last Modification Date", "Download .RAP file", "File Size", "SHA256",
      ]
    case (.PSP, .Game):
      expectedHeader = [
        "Title ID", "Region", "Type", "Name", "PKG direct link", "Content ID",
        "Last Modification Date", "RAP", "Download .RAP file", "File Size", "SHA256",
      ]
    case (.PSP, .DLC):
      expectedHeader = [
        "Title ID", "Region", "Name", "PKG direct link", "Content ID", "Last Modification Date",
        "RAP", "Download .RAP file", "File Size", "SHA256",
      ]
    case (.PSM, .Game):
      expectedHeader = [
        "Title ID", "Region", "Name", "PKG direct link", "zRIF", "Content ID",
        "Last Modification Date", "File Size", "SHA256",
      ]
    case (.PSX, .Game):
      expectedHeader = [
        "Title ID", "Region", "Name", "PKG direct link", "Content ID", "Last Modification Date",
        "Original Name", "File Size", "SHA256",
      ]
    default: throw CatalogParseError.unsupportedKind(kind)
    }
    let headerColumns = header.components(separatedBy: "\t").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    let expectedColumns = expectedHeader.map { $0.lowercased() }
    guard headerColumns.count >= expectedColumns.count,
      Array(headerColumns.prefix(expectedColumns.count)) == expectedColumns
    else { throw CatalogParseError.invalidHeader(kind) }
    let expectedCount = expectedHeader.count

    var output: [CatalogItem] = []
    for lineIndex in (firstNonEmpty + 1)..<lines.count {
      let line = lines[lineIndex]
      guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
      let values = line.components(separatedBy: "\t")
      let rowNumber = lineIndex + 1
      guard values.count >= expectedCount else {
        throw CatalogParseError.wrongColumnCount(
          row: rowNumber,
          expectedAtLeast: expectedCount,
          found: values.count
        )
      }
      output.append(try parse(values, kind: kind, row: rowNumber))
    }
    guard !output.isEmpty else { throw CatalogParseError.emptyCatalogue }
    return output
  }

  static func isValidTitleID(_ value: String) -> Bool {
    guard value.count == 9 else { return false }
    let letters = value.prefix(4).unicodeScalars
    let digits = value.suffix(5).unicodeScalars
    return letters.allSatisfy { $0.isASCII && CharacterSet.letters.contains($0) }
      && digits.allSatisfy { $0.value >= 48 && $0.value <= 57 }
  }
}
