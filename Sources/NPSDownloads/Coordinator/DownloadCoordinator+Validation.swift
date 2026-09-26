import Foundation
import NPSCore

extension DownloadCoordinator {
  func validate(_ request: DownloadJobRequest) throws {
    guard let scheme = request.sourceURL.scheme?.lowercased(), ["http", "https"].contains(scheme),
      request.sourceURL.host != nil
    else {
      throw DownloadCoordinatorError.invalidRequest(LocalizedMessage("error.download.invalidURL"))
    }
    guard !Self.safeFileName(request.fileNameTitle).isEmpty,
      !Self.safePathComponent(request.consoleType).isEmpty
    else {
      throw DownloadCoordinatorError.invalidRequest(
        LocalizedMessage("error.download.unsafePathComponents")
      )
    }
    guard request.expectedByteCount == nil || request.expectedByteCount! > 0 else {
      throw DownloadCoordinatorError.invalidRequest(
        LocalizedMessage("error.download.invalidExpectedSize")
      )
    }
    guard Self.isValidExtension(request.fileExtension) else {
      throw DownloadCoordinatorError.invalidRequest(
        LocalizedMessage("error.download.unsafeExtension")
      )
    }
    if let digest = request.sha256, !Self.isValidDigest(digest) {
      throw DownloadCoordinatorError.invalidRequest(
        LocalizedMessage("error.download.invalidSHA256")
      )
    }
    if let patchURL = request.compatibilityPatchURL {
      guard request.fileExtension.lowercased() == "ppk", request.titleID != nil else {
        throw DownloadCoordinatorError.invalidRequest(
          LocalizedMessage("error.download.patchRequiresTitleID")
        )
      }
      guard let scheme = patchURL.scheme?.lowercased(), ["http", "https"].contains(scheme),
        patchURL.host != nil
      else {
        throw DownloadCoordinatorError.invalidRequest(
          LocalizedMessage("error.download.invalidPatchURL")
        )
      }
    }
    if request.fileExtension.lowercased() == "ppk", request.extractAfterDownload,
      request.titleID == nil
    {
      throw DownloadCoordinatorError.invalidRequest(
        LocalizedMessage("error.download.extractionRequiresTitleID")
      )
    }
    if request.compatibilityPatchMode == .overlayExistingOutput {
      guard request.fileExtension.lowercased() == "ppk", request.titleID != nil,
        request.compatibilityPatchURL == nil
      else {
        throw DownloadCoordinatorError.invalidRequest(
          LocalizedMessage("error.download.invalidPatchOverlay")
        )
      }
    }
  }

  private static func isValidExtension(_ value: String) -> Bool {
    !value.isEmpty && value.count <= 10
      && value.unicodeScalars.allSatisfy {
        CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains($0)
      }
  }

  private static func isValidDigest(_ digest: String) -> Bool {
    digest.count == 64
      && digest.unicodeScalars.allSatisfy {
        CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
      }
  }
}
