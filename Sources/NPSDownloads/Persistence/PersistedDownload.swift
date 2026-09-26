import Foundation
import NPSCore

struct PersistedDownload: Codable, Sendable {
  var id: UUID
  var request: DownloadJobRequest
  var state: DownloadState
  var progress: Double
  var bytesReceived: Int64
  var destinationDirectory: URL
  var destinationVolumeUUID: String?
  var destinationURL: URL?
  var verifiedPackage: Bool?
  var compatibilityPatchDestinationURL: URL?
  var compatibilityPatchVerified: Bool?
  var activeTransfer: PersistedTransferArtifact?
  var extractedDirectoryURL: URL?
  var legacyOutputLocationUnknown: Bool?
  /// Rendered when the message was stored. Records written before
  /// `errorDetail` existed only have this, and older builds still read it.
  var errorMessage: String?
  var resumeData: Data?
  var createdAt: Date
  var updatedAt: Date
  /// Language-independent form of `errorMessage`, rendered when displayed.
  var errorDetail: LocalizedMessage?

  /// Records `message` in both forms; `nil` clears the error.
  mutating func setError(_ message: LocalizedMessage?) {
    errorDetail = message
    errorMessage = message.map(DownloadSnapshot.displayText(for:))
  }

  /// The error in the current language, or the stored text of an older record.
  var displayedErrorMessage: String? {
    errorDetail.map(DownloadSnapshot.displayText(for:)) ?? errorMessage
  }

  private var recordsMissingLegacyOutput: Bool {
    guard let errorDetail else {
      return errorMessage?.hasPrefix(DownloadSnapshot.legacyOutputLocationMissingPrefix) == true
    }
    return errorDetail.key == DownloadSnapshot.legacyOutputLocationMissingKey
  }

  var snapshot: DownloadSnapshot {
    let visibleErrorMessage: String?
    if state == .complete, let extractedDirectoryURL {
      var isDirectory: ObjCBool = false
      let outputIsAvailable =
        FileManager.default.fileExists(
          atPath: extractedDirectoryURL.path,
          isDirectory: &isDirectory
        ) && isDirectory.boolValue
      if outputIsAvailable {
        visibleErrorMessage = recordsMissingLegacyOutput ? nil : displayedErrorMessage
      } else {
        visibleErrorMessage = DownloadSnapshot.displayText(
          for: DownloadSnapshot.legacyOutputLocationMissingMessage(for: extractedDirectoryURL)
        )
      }
    } else {
      visibleErrorMessage = displayedErrorMessage
    }
    return DownloadSnapshot(
      id: id,
      request: request,
      state: state,
      progress: progress,
      bytesReceived: bytesReceived,
      destinationDirectory: destinationDirectory,
      destinationURL: destinationURL,
      packageVerified: verifiedPackage == true,
      compatibilityPatchDestinationURL: compatibilityPatchDestinationURL,
      compatibilityPatchVerified: compatibilityPatchVerified == true,
      extractedDirectoryURL: extractedDirectoryURL,
      legacyOutputLocationUnknown: legacyOutputLocationUnknown,
      errorMessage: visibleErrorMessage,
      canResume: resumeData != nil || (state == .paused && bytesReceived == 0),
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }
}
