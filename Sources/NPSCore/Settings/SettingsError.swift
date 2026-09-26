import Foundation

public enum SettingsError: Error, Equatable, LocalizedMessageError, Sendable {
  case invalidCatalogueURL(CatalogSource, String)
  case invalidDownloadDirectory(URL)
  case invalidConcurrency(Int)

  public var localizedMessage: LocalizedMessage {
    switch self {
    case let .invalidCatalogueURL(source, value):
      LocalizedMessage(
        "error.settings.invalidCatalogueURL",
        .message(source.localizedTitleMessage),
        .text(value)
      )
    case let .invalidDownloadDirectory(url):
      LocalizedMessage("error.settings.invalidDownloadDirectory", .text(url.absoluteString))
    case let .invalidConcurrency(value):
      LocalizedMessage("error.settings.invalidConcurrency", .integer(value))
    }
  }
}
