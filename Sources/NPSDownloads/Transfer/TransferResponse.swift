import Foundation

struct TransferResponse: Sendable {
  let statusCode: Int
  let mimeType: String?
  let expectedContentLength: Int64
}
