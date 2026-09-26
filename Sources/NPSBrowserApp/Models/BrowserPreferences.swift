import Foundation
import NPSCore

struct BrowserPreferences: Sendable {
  var catalogueURLs: [CatalogSource: URL]
  /// The effective output folder used by new jobs (`dl_library_folder` in the legacy app).
  var downloadDirectory: URL
  var concurrentDownloads: Int
  var extraction: ExtractionSettings
  var hideInvalidURLItems: Bool
}
