import Foundation

public struct AppSettings: Equatable, Sendable {
  public let catalogueURLs: [CatalogSource: URL]
  public let downloadDirectory: URL
  public let downloadLibraryDirectory: URL
  public let concurrentDownloads: Int
  public let extraction: ExtractionSettings
  public let hideInvalidURLItems: Bool

  public init(
    catalogueURLs: [CatalogSource: URL],
    downloadDirectory: URL,
    downloadLibraryDirectory: URL? = nil,
    concurrentDownloads: Int,
    extraction: ExtractionSettings,
    hideInvalidURLItems: Bool = true
  ) {
    self.catalogueURLs = catalogueURLs
    self.downloadDirectory = downloadDirectory
    self.downloadLibraryDirectory =
      downloadLibraryDirectory
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Downloads",
        isDirectory: true
      ).appendingPathComponent("NPS Downloads", isDirectory: true)
    self.concurrentDownloads = max(1, concurrentDownloads)
    self.extraction = extraction
    self.hideInvalidURLItems = hideInvalidURLItems
  }
}
