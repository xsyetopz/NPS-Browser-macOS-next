import Foundation

public struct CompatibilityPack: Codable, Equatable, Identifiable, Sendable {
  public let titleID: String
  public let downloadURL: URL
  public let kind: CompatibilityPackKind
  public let displayName: String?

  public var id: String { "\(kind.rawValue):\(titleID):\(downloadURL.absoluteString)" }

  public init(
    titleID: String,
    downloadURL: URL,
    kind: CompatibilityPackKind,
    displayName: String? = nil
  ) {
    self.titleID = titleID
    self.downloadURL = downloadURL
    self.kind = kind
    self.displayName = displayName
  }
}
