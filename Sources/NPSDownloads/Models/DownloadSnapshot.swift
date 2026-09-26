import Foundation
import NPSCore

public struct DownloadSnapshot: Identifiable, Codable, Hashable, Sendable {
  static let legacyOutputLocationUnknownPrefix = "legacy-output-location-unknown:"
  static let legacyOutputLocationMissingPrefix = "legacy-output-location-missing:"

  static let legacyOutputLocationUnknownKey = "error.migration.outputLocationUnknown"
  static let legacyOutputLocationMissingKey = "error.migration.outputLocationMissing"

  static func legacyOutputLocationMissingMessage(for folder: URL) -> LocalizedMessage {
    LocalizedMessage(legacyOutputLocationMissingKey, .text(folder.path))
  }

  /// Renders a stored job message in the current language. Legacy output
  /// location messages keep their machine-readable prefix.
  static func displayText(for message: LocalizedMessage) -> String {
    let text = message.resolved()
    return switch message.key {
    case legacyOutputLocationUnknownKey: legacyOutputLocationUnknownPrefix + " " + text
    case legacyOutputLocationMissingKey: legacyOutputLocationMissingPrefix + " " + text
    default: text
    }
  }

  public let id: UUID
  public let request: DownloadJobRequest
  public let state: DownloadState
  public let progress: Double
  public let bytesReceived: Int64
  public let destinationDirectory: URL
  public let destinationURL: URL?
  public let packageVerified: Bool
  public let compatibilityPatchDestinationURL: URL?
  public let compatibilityPatchVerified: Bool
  public let extractedDirectoryURL: URL?
  public let legacyOutputLocationUnknown: Bool?
  public let errorMessage: String?
  public let canResume: Bool
  public let createdAt: Date
  public let updatedAt: Date

  public var completedURL: URL? {
    if state == .complete, let extractedDirectoryURL {
      var isDirectory: ObjCBool = false
      guard
        FileManager.default.fileExists(
          atPath: extractedDirectoryURL.path,
          isDirectory: &isDirectory
        ), isDirectory.boolValue
      else { return nil }
      return extractedDirectoryURL
    }
    if state == .complete, legacyOutputLocationUnknown == true { return nil }
    // Pre-integrity legacy jobs were marked complete from transfer status
    // alone. Keep their recorded file revealable without claiming it passed
    // the current package verifier.
    if state == .complete, let destinationURL,
      FileManager.default.fileExists(atPath: destinationURL.path)
    {
      return destinationURL
    }
    if let destinationURL, packageVerified,
      FileManager.default.fileExists(atPath: destinationURL.path),
      state == .complete || state == .extracting || state == .failed
    {
      return destinationURL
    }
    return nil
  }

  public var hasVerifiedPackage: Bool {
    guard packageVerified, let destinationURL else { return false }
    guard FileManager.default.fileExists(atPath: destinationURL.path) else { return false }
    guard request.compatibilityPatchURL != nil else { return true }
    guard compatibilityPatchVerified, let compatibilityPatchDestinationURL else { return false }
    return FileManager.default.fileExists(atPath: compatibilityPatchDestinationURL.path)
  }

  public var canRestart: Bool { state == .failed || (state == .paused && !canResume) }
}
