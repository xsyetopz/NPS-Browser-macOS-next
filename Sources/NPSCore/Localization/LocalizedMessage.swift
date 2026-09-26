import Foundation

/// User-facing text kept language-independent until it is shown: a catalog key
/// with typed arguments, or text that was never in the catalog (system error
/// descriptions, tool output, records written before messages were structured).
///
/// Errors carry it instead of rendered sentences, so their equality does not
/// depend on the UI language, and it is `Codable` so persisted state can be
/// rendered again in whatever language is current when it is displayed.
public indirect enum LocalizedMessage: Codable, Hashable, Sendable {
  case key(String, arguments: [Argument])
  case text(String)

  public enum Argument: Codable, Hashable, Sendable {
    /// Inserted verbatim: paths, identifiers, tool output.
    case text(String)
    case integer(Int)
    /// A nested message, rendered in the same language as its parent.
    case message(LocalizedMessage)
    /// A `.stringsdict` plural rendered for `count`.
    case plural(String, count: Int)
  }

  public init(_ key: String, _ arguments: Argument...) { self = .key(key, arguments: arguments) }

  /// The structured message of an error that has one, otherwise its description.
  public init(_ error: any Error) {
    if let error = error as? any LocalizedMessageError {
      self = error.localizedMessage
    } else {
      self = .text(error.localizedDescription)
    }
  }

  /// The catalog key, or `nil` for text outside the catalog.
  public var key: String? {
    guard case let .key(key, _) = self else { return nil }
    return key
  }

  public func resolved(in localization: Localization = .current) -> String {
    switch self {
    case let .text(text): return text
    case let .key(key, arguments) where arguments.isEmpty: return localization.string(key)
    case let .key(key, arguments):
      return localization.formatted(
        key,
        arguments: arguments.map { $0.formatArgument(in: localization) }
      )
    }
  }
}

extension LocalizedMessage.Argument {
  func formatArgument(in localization: Localization) -> any CVarArg {
    switch self {
    case let .text(text): text
    case let .integer(value): value
    case let .message(message): message.resolved(in: localization)
    case let .plural(key, count): localization.plural(key, count: count)
    }
  }
}

/// An error whose description is a `LocalizedMessage`, rendered when read.
public protocol LocalizedMessageError: LocalizedError {
  var localizedMessage: LocalizedMessage { get }
}

extension LocalizedMessageError {
  public var errorDescription: String? { localizedMessage.resolved() }
}
