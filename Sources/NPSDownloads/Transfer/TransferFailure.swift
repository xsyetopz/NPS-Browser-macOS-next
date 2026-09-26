import Foundation
import NPSCore

struct TransferFailure: LocalizedMessageError, Sendable {
  let message: LocalizedMessage
  let resumeData: Data?

  var localizedMessage: LocalizedMessage { message }
}
