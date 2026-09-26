import Foundation

struct VerifiedDownload: Sendable {
  let temporaryURL: URL
  let byteCount: Int64
  let sha256: String
}
