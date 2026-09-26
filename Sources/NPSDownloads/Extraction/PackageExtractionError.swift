import Foundation
import NPSCore

public enum PackageExtractionError: Error, LocalizedMessageError, Sendable {
  case unsupportedConsole(String)
  case missingHelper(URL)
  case launchFailed(LocalizedMessage)
  /// `output` is the helper's diagnostic text, or a catalog message when it wrote none.
  case failed(exitCode: Int32, output: LocalizedMessage)

  public var localizedMessage: LocalizedMessage {
    switch self {
    case let .unsupportedConsole(console):
      LocalizedMessage("error.extraction.unsupportedConsole", .text(console))
    case let .missingHelper(url):
      LocalizedMessage("error.extraction.missingHelper", .text(url.path))
    case let .launchFailed(reason):
      LocalizedMessage("error.extraction.launchFailed", .message(reason))
    case let .failed(exitCode, output):
      LocalizedMessage(
        "error.extraction.failed",
        .integer(Int(exitCode)),
        .message(output == .text("") ? LocalizedMessage("error.extraction.noOutput") : output)
      )
    }
  }

  /// `error` as a launch failure, unless it already is an extraction error.
  static func launchFailure(wrapping error: any Error) -> Self {
    error as? Self ?? .launchFailed(LocalizedMessage(error))
  }
}
