import Foundation

public enum FileType: String, CaseIterable, Codable, Hashable, Sendable {
  case Game
  case Update
  case DLC
  case Theme
  case Avatar
  case CPack
  case CPatch
  case RAP
}
