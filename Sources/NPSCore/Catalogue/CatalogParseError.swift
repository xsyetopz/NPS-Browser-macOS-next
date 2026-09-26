import Foundation

public enum CatalogParseError: Error, Equatable, LocalizedMessageError, Sendable {
  case emptyInput
  case emptyCatalogue
  case missingHeader
  case invalidHeader(CatalogKind)
  case invalidTitleID(String)
  case unsupportedKind(CatalogKind)
  case wrongColumnCount(row: Int, expectedAtLeast: Int, found: Int)
  case missingField(row: Int, field: String)
  /// A row has none of the fields that identify an item.
  case missingIdentity(row: Int)
  case invalidField(row: Int, field: String, value: String)
  /// The parser's own description, or `nil` when it gave none.
  case malformedXML(String?)
  case missingUpdateURL
  case invalidCompatibilityEntry(row: Int, reason: CompatibilityEntryIssue)

  public var localizedMessage: LocalizedMessage {
    switch self {
    case .emptyInput: LocalizedMessage("error.catalogue.emptyInput")
    case .emptyCatalogue: LocalizedMessage("error.catalogue.emptyCatalogue")
    case .missingHeader: LocalizedMessage("error.catalogue.missingHeader")
    case let .invalidHeader(kind):
      LocalizedMessage(
        "error.catalogue.invalidHeader",
        .message(kind.console.localizedTitleMessage),
        .message(kind.fileType.localizedTitleMessage)
      )
    case let .invalidTitleID(value):
      LocalizedMessage("error.catalogue.invalidTitleID", .text(value))
    case let .unsupportedKind(kind):
      LocalizedMessage(
        "error.catalogue.unsupportedKind",
        .message(kind.console.localizedTitleMessage),
        .message(kind.fileType.localizedTitleMessage)
      )
    case let .wrongColumnCount(row, expected, found):
      LocalizedMessage(
        "error.catalogue.wrongColumnCount",
        .integer(row),
        .plural("error.catalogue.columnCount", count: found),
        .plural("error.catalogue.columnCount", count: expected)
      )
    case let .missingField(row, field):
      LocalizedMessage("error.catalogue.missingField", .integer(row), .text(field))
    case let .missingIdentity(row):
      LocalizedMessage(
        "error.catalogue.missingField",
        .integer(row),
        .message(LocalizedMessage("error.catalogue.identityFields"))
      )
    case let .invalidField(row, field, value):
      LocalizedMessage("error.catalogue.invalidField", .integer(row), .text(field), .text(value))
    case let .malformedXML(message):
      LocalizedMessage(
        "error.catalogue.malformedXML",
        .message(
          message.map(LocalizedMessage.text)
            ?? LocalizedMessage("error.catalogue.unknownParserError")
        )
      )
    case .missingUpdateURL: LocalizedMessage("error.catalogue.missingUpdateURL")
    case let .invalidCompatibilityEntry(row, reason):
      LocalizedMessage(
        "error.catalogue.invalidCompatibilityEntry",
        .integer(row),
        .message(reason.localizedMessage)
      )
    }
  }
}

/// Why a compatibility-feed row was rejected. Raw values name the catalog keys
/// `error.catalogue.compatibility.<rawValue>`.
public enum CompatibilityEntryIssue: String, CaseIterable, Codable, Sendable {
  case missingSeparator
  case missingPathOrName
  case invalidPackPath
  case invalidPatchPath
  case unsafePath
  case invalidTitleID
  case invalidExtension
  case invalidURL

  public var localizedMessage: LocalizedMessage {
    LocalizedMessage("error.catalogue.compatibility.\(rawValue)")
  }
}
