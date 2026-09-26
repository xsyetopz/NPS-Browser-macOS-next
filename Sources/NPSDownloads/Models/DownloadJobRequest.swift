import Foundation

public struct DownloadJobRequest: Codable, Hashable, Sendable {
  public let sourceURL: URL
  public let title: String
  public let consoleType: String
  public let titleID: String?
  public let expectedByteCount: Int64?
  public let sha256: String?
  public let fileExtension: String
  public let extractAfterDownload: Bool
  public let zrif: String?
  public let extractionOptions: PackageExtractionOptions
  public let compatibilityPatchURL: URL?
  /// Optional for backward-compatible decoding of queue files written before
  /// the patch-only overlay workflow existed.
  public let compatibilityPatchMode: CompatibilityPatchMode?
  /// Language-independent title for the names of downloaded files and output
  /// folders, when `title` is a localized display title. Optional so queue
  /// files written before it existed still decode; they fall back to `title`.
  public let fileTitle: String?

  public init(
    sourceURL: URL,
    title: String,
    consoleType: String,
    titleID: String? = nil,
    expectedByteCount: Int64? = nil,
    sha256: String? = nil,
    fileExtension: String = "pkg",
    extractAfterDownload: Bool = false,
    zrif: String? = nil,
    extractionOptions: PackageExtractionOptions = PackageExtractionOptions(),
    compatibilityPatchURL: URL? = nil,
    compatibilityPatchMode: CompatibilityPatchMode? = nil,
    fileTitle: String? = nil
  ) {
    self.sourceURL = sourceURL
    self.title = title
    self.consoleType = consoleType
    self.titleID = titleID
    self.expectedByteCount = expectedByteCount
    self.sha256 = sha256
    self.fileExtension = fileExtension
    self.extractAfterDownload = extractAfterDownload
    self.zrif = zrif
    self.extractionOptions = extractionOptions
    self.compatibilityPatchURL = compatibilityPatchURL
    self.compatibilityPatchMode = compatibilityPatchMode
    self.fileTitle = fileTitle
  }

  /// The title that names files and folders on disk.
  var fileNameTitle: String { fileTitle ?? title }
}
