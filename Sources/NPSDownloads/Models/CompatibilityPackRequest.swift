import Foundation

/// A compatibility pack and its optional matching patch. The coordinator
/// downloads these files in order and applies the patch when extraction is enabled.
public struct CompatibilityPackRequest: Hashable, Sendable {
  public let titleID: String
  public let title: String
  public let packURL: URL
  public let patchURL: URL?
  public let extractAfterDownload: Bool

  public init(
    titleID: String,
    title: String,
    packURL: URL,
    patchURL: URL? = nil,
    extractAfterDownload: Bool = true
  ) {
    self.titleID = titleID
    self.title = title
    self.packURL = packURL
    self.patchURL = patchURL
    self.extractAfterDownload = extractAfterDownload
  }
}
