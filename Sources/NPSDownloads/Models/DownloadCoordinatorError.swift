import Foundation
import NPSCore

public enum DownloadCoordinatorError: Error, LocalizedMessageError, Sendable {
  case invalidRequest(LocalizedMessage)
  case invalidTransition(from: DownloadState, to: DownloadState)
  case missingJob(UUID)
  case invalidResumeData
  case downloadUnavailable(LocalizedMessage)
  case persistenceFailure(String)

  public var localizedMessage: LocalizedMessage {
    switch self {
    case let .invalidRequest(message): message
    case let .invalidTransition(from, to):
      LocalizedMessage(
        "error.download.invalidTransition",
        .message(from.localizedTitleMessage),
        .message(to.localizedTitleMessage)
      )
    case let .missingJob(id): LocalizedMessage("error.download.missingJob", .text(id.uuidString))
    case .invalidResumeData: LocalizedMessage("error.download.invalidResumeData")
    case let .downloadUnavailable(message): message
    case let .persistenceFailure(details):
      LocalizedMessage("error.download.persistenceFailure", .text(details))
    }
  }
}
