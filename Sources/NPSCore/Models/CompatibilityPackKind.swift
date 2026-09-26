import Foundation

public enum CompatibilityPackKind: String, CaseIterable, Codable, Hashable, Sendable {
  case pack = "CompatPack"
  case patch = "CompatPatch"

  public var fileType: FileType {
    switch self {
    case .pack: .CPack
    case .patch: .CPatch
    }
  }
}
