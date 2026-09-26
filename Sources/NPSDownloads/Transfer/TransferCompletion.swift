import Foundation

struct TransferCompletion: Sendable {
  let temporaryURL: URL
  let response: TransferResponse
}
