import Foundation
import NPSBrowserAppResources
import NPSCore

enum CatalogueRefreshError: Error, LocalizedError, Sendable {
  case invalidURL(URL)
  case invalidResponse(URL)
  case httpStatus(URL, Int)
  case invalidText(URL)
  case partialFailure([CatalogueSourceFailure])
  case itemUnavailable(LocalizedMessage)

  var errorDescription: String? {
    switch self {
    case let .invalidURL(url):
      String(format: AppResources.localized("error.refresh.invalidURL"), url.absoluteString)
    case let .invalidResponse(url):
      String(format: AppResources.localized("error.refresh.invalidResponse"), url.absoluteString)
    case let .httpStatus(url, code):
      String(
        format: AppResources.localized("error.refresh.httpStatus"),
        url.host ?? url.absoluteString,
        code
      )
    case let .invalidText(url):
      String(
        format: AppResources.localized("error.refresh.invalidText"),
        url.host ?? url.absoluteString
      )
    case let .partialFailure(failures):
      ([AppResources.localized("error.refresh.partialFailure")] + failures.map(\.localizedLine))
        .joined(separator: "\n")
    case let .itemUnavailable(reason):
      LocalizedMessage("error.refresh.itemUnavailable", .message(reason)).resolved()
    }
  }
}
