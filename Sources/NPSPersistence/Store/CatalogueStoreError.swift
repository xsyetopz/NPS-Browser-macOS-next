import Foundation
import NPSCore

public enum CatalogueStoreError: Error, Equatable, LocalizedMessageError, Sendable {
  case invalidRealmURL(URL)
  case mismatchedCompatibilityPackKind(expected: CompatibilityPackKind)

  public var localizedMessage: LocalizedMessage {
    switch self {
    case let .invalidRealmURL(url):
      LocalizedMessage("error.store.invalidRealmURL", .text(url.absoluteString))
    case let .mismatchedCompatibilityPackKind(expected):
      LocalizedMessage(
        "error.store.mismatchedCompatibilityPackKind",
        .message(expected.fileType.localizedTitleMessage)
      )
    }
  }
}
