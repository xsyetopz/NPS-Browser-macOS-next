import Foundation

enum PersistedTransferArtifact: String, Codable, Sendable {
  case primary
  case compatibilityPatch
}
