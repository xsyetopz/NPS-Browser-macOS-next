import Foundation
import NPSCore

enum CompatibilityPackArchiveError: Error, LocalizedMessageError, Sendable {
  case invalidArchive(LocalizedMessage)
  case unsafeEntry(String, LocalizedMessage)
  case extraction(LocalizedMessage)
  case destination(LocalizedMessage)

  var localizedMessage: LocalizedMessage {
    switch self {
    case let .invalidArchive(reason): LocalizedMessage("error.archive.invalid", .message(reason))
    case let .unsafeEntry(name, reason):
      LocalizedMessage("error.archive.unsafeEntry", .text(name), .message(reason))
    case let .extraction(reason): LocalizedMessage("error.archive.extraction", .message(reason))
    case let .destination(reason): LocalizedMessage("error.archive.destination", .message(reason))
    }
  }
}
