import Foundation
import NPSCore

extension ApplicationDataSource {
  func loadPreferences() throws -> BrowserPreferences {
    let snapshot = settings.snapshot()
    return BrowserPreferences(
      catalogueURLs: snapshot.catalogueURLs,
      downloadDirectory: snapshot.downloadLibraryDirectory,
      concurrentDownloads: snapshot.concurrentDownloads,
      extraction: snapshot.extraction,
      hideInvalidURLItems: snapshot.hideInvalidURLItems
    )
  }

  func savePreferences(_ preferences: BrowserPreferences) throws {
    if let failure = preferences.validationFailure { throw Self.settingsError(for: failure) }
    for (source, url) in preferences.catalogueURLs {
      try settings.setCatalogueURL(url, for: source)
    }
    // `dl_library_folder` is the folder that the legacy transfer and extraction
    // managers actually used. New jobs snapshot it at enqueue time; persisted
    // jobs keep their existing recorded destinations.
    try settings.setDownloadLibraryDirectory(preferences.downloadDirectory)
    try settings.setConcurrentDownloads(preferences.concurrentDownloads)
    settings.updateExtractionSettings(preferences.extraction)
    settings.setHidesInvalidURLItems(preferences.hideInvalidURLItems)
  }

  private static func settingsError(
    for failure: BrowserPreferences.ValidationFailure
  ) -> SettingsError {
    switch failure {
    case let .invalidDownloadDirectory(url): .invalidDownloadDirectory(url)
    case let .invalidConcurrency(value): .invalidConcurrency(value)
    case let .invalidCatalogueURL(source, value): .invalidCatalogueURL(source, value)
    }
  }
}
