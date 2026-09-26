import Foundation
import NPSCore

enum LegacyDownloadMigrationError: Error, LocalizedMessageError, Sendable {
  case malformedArchive(String)
  case invalidItem(index: Int, reason: LegacyDownloadItemIssue)
  case backupFailed(String)
  case invalidImportLedger(LocalizedMessage)
  case importLedgerWriteFailed(String)

  var localizedMessage: LocalizedMessage {
    switch self {
    case let .malformedArchive(details):
      LocalizedMessage("error.migration.malformedArchive", .text(details))
    case let .invalidItem(index, reason):
      LocalizedMessage(
        "error.migration.invalidItem",
        .integer(index + 1),
        .message(LocalizedMessage("error.migration.\(reason.rawValue)"))
      )
    case let .backupFailed(details):
      LocalizedMessage("error.migration.backupFailed", .text(details))
    case let .invalidImportLedger(details):
      LocalizedMessage("error.migration.invalidImportLedger", .message(details))
    case let .importLedgerWriteFailed(details):
      LocalizedMessage("error.migration.importLedgerWriteFailed", .text(details))
    }
  }
}

/// Why an archived queue item cannot be imported. Raw values name the catalog
/// keys `error.migration.<rawValue>`.
enum LegacyDownloadItemIssue: String, CaseIterable, Sendable {
  case unsafeURL
  case missingConsole
  case missingName
  case nonLocalDestination
}
