import Foundation
import NPSCore

enum DownloadValidationError: Error, LocalizedMessageError, Sendable {
  case httpStatus(Int)
  case invalidContentType(String)
  case errorDocument
  case invalidPackageHeader(PackageHeaderIssue)
  case invalidCompatibilityHeader
  case invalidRAPPayload
  case lengthMismatch(expected: Int64, actual: Int64)
  case hashMismatch(expected: String, actual: String)
  case destinationUnavailable(LocalizedMessage)

  var localizedMessage: LocalizedMessage {
    switch self {
    case let .httpStatus(status): LocalizedMessage("error.download.httpStatus", .integer(status))
    case let .invalidContentType(type):
      LocalizedMessage("error.download.invalidContentType", .text(type))
    case .errorDocument: LocalizedMessage("error.download.errorDocument")
    case let .invalidPackageHeader(issue):
      LocalizedMessage(
        "error.download.invalidPackageHeader",
        .message(LocalizedMessage("error.download.header.\(issue.rawValue)"))
      )
    case .invalidCompatibilityHeader: LocalizedMessage("error.download.invalidCompatibilityHeader")
    case .invalidRAPPayload: LocalizedMessage("error.download.invalidRAPPayload")
    case let .lengthMismatch(expected, actual):
      LocalizedMessage(
        "error.download.lengthMismatch",
        .plural("error.download.byteCount", count: Int(clamping: actual)),
        .plural("error.download.byteCount", count: Int(clamping: expected))
      )
    case let .hashMismatch(expected, actual):
      LocalizedMessage("error.download.hashMismatch", .text(expected), .text(actual))
    case let .destinationUnavailable(reason):
      LocalizedMessage("error.download.destinationUnavailable", .message(reason))
    }
  }
}

/// Which minimum PKG header check failed. Raw values name the catalog keys
/// `error.download.header.<rawValue>`.
enum PackageHeaderIssue: String, CaseIterable, Sendable {
  case tooShort
  case missingSignature
  case missingExtendedSignature
  case lengthOutsideFile
  case unsupportedKeyType
  case inconsistentOffsets
  case itemTableOutsidePackage
  case metadataCountExceedsRegion
  case metadataBeyondBoundary
  case metadataEntryTruncated
  case metadataEntryExceedsRegion
  case contentTypeTruncated
  case itemTableTruncated
  case itemTableMissing
}
