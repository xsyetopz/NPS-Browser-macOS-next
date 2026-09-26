import Foundation
import NPSBrowserAppResources
import NPSCore

extension BrowserPreferences {
  enum ValidationFailure: Error, Equatable, Sendable {
    case invalidCatalogueURL(CatalogSource, String)
    case invalidDownloadDirectory(URL)
    case invalidConcurrency(Int)

    var formMessage: String {
      switch self {
      case let .invalidCatalogueURL(source, _):
        "\(AppResources.localized("preferences.invalidCatalogueURL"))\n\(source.localizedTitle)"
      case .invalidDownloadDirectory: AppResources.localized("preferences.invalidDownloadFolder")
      case let .invalidConcurrency(value):
        SettingsError.invalidConcurrency(value).localizedDescription
      }
    }
  }

  static func isSupportedCatalogueURL(_ url: URL) -> Bool {
    if url.isFileURL {
      return
        (url.host == nil || url.host?.isEmpty == true
        || url.host?.caseInsensitiveCompare("localhost") == .orderedSame) && url.user == nil
        && url.password == nil && url.path.hasPrefix("/")
    }
    guard url.absoluteURL == url, let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty, url.user == nil,
      url.password == nil
    else { return false }
    return true
  }

  static func isValidDownloadDirectory(_ url: URL) -> Bool {
    url.isFileURL && url.path.hasPrefix("/")
  }

  /// Applies one catalogue URL typed into the form, checking that it is supported.
  func applyingCatalogueURL(
    _ text: String,
    for source: CatalogSource
  ) -> Result<BrowserPreferences, ValidationFailure> {
    guard let url = URL(string: text), Self.isSupportedCatalogueURL(url) else {
      return .failure(.invalidCatalogueURL(source, text))
    }
    var updated = self
    updated.catalogueURLs[source] = url
    return .success(updated)
  }

  /// Applies the form's non-URL values, checking the download folder.
  func applying(_ values: PreferencesFormValues) -> Result<BrowserPreferences, ValidationFailure> {
    var updated = self
    let directoryURL = URL(fileURLWithPath: values.downloadDirectoryPath, isDirectory: true)
    guard Self.isValidDownloadDirectory(directoryURL) else {
      return .failure(.invalidDownloadDirectory(directoryURL))
    }
    updated.downloadDirectory = directoryURL
    updated.concurrentDownloads = values.concurrentDownloads
    updated.hideInvalidURLItems = values.hideInvalidURLItems
    updated.extraction = ExtractionSettings(
      extractAfterDownload: values.extractAfterDownload,
      keepPackage: values.keepPackage,
      saveAsZip: values.saveAsZip,
      createLicense: values.createLicense,
      compressPSPISO: values.compressPSPISO,
      compressionFactor: values.compressionFactor,
      unpackPS3Packages: extraction.unpackPS3Packages
    )
    return .success(updated)
  }

  /// Checks a complete value before it is saved: the download folder, the
  /// concurrency, then every catalogue URL.
  var validationFailure: ValidationFailure? {
    guard Self.isValidDownloadDirectory(downloadDirectory) else {
      return .invalidDownloadDirectory(downloadDirectory)
    }
    guard concurrentDownloads > 0 else { return .invalidConcurrency(concurrentDownloads) }
    for (source, url) in catalogueURLs where !Self.isSupportedCatalogueURL(url) {
      return .invalidCatalogueURL(source, url.absoluteString)
    }
    return nil
  }
}
