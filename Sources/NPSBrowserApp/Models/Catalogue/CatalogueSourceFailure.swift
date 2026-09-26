import Foundation
import NPSCore

/// One catalogue source that failed to refresh, kept language-independent
/// until the refresh error is shown.
struct CatalogueSourceFailure: Hashable, Sendable {
  let source: CatalogSource
  let reason: LocalizedMessage

  /// The source's localized title and the reason, as one line.
  var localizedLine: String {
    LocalizedMessage(
      "error.refresh.sourceFailure",
      .message(source.localizedTitleMessage),
      .message(reason)
    ).resolved()
  }
}
