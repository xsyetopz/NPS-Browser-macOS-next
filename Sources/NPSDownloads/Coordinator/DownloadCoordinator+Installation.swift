import Foundation
import NPSCore

extension DownloadCoordinator {
  func install(
    _ validated: VerifiedDownload,
    for job: PersistedDownload,
    artifact: PersistedTransferArtifact
  ) async throws -> URL {
    let plannedTarget: URL
    let collisionTitle: String
    let collisionExtension: String
    switch artifact {
    case .primary:
      collisionTitle = job.request.fileNameTitle
      collisionExtension = job.request.fileExtension
      plannedTarget =
        job.destinationURL ?? nextAvailableURL(for: job.request, in: job.destinationDirectory)
    case .compatibilityPatch:
      collisionTitle = "\(job.request.fileNameTitle) CPatch"
      collisionExtension = "ppk"
      plannedTarget =
        job.compatibilityPatchDestinationURL
        ?? nextAvailableURL(
          title: collisionTitle,
          fileExtension: collisionExtension,
          in: job.destinationDirectory
        )
    }
    let libraryRoot = job.destinationDirectory.deletingLastPathComponent()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: libraryRoot.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw DownloadValidationError.destinationUnavailable(
        LocalizedMessage("error.download.folderMissing")
      )
    }
    if let expectedVolume = job.destinationVolumeUUID {
      let currentVolume = try? libraryRoot.resourceValues(forKeys: [.volumeUUIDStringKey])
        .volumeUUIDString
      guard currentVolume == expectedVolume else {
        throw DownloadValidationError.destinationUnavailable(
          LocalizedMessage("error.download.volumeChanged")
        )
      }
    }
    let target: URL
    if FileManager.default.fileExists(atPath: plannedTarget.path) {
      reservedPaths.remove(plannedTarget.path)
      target = nextAvailableURL(
        title: collisionTitle,
        fileExtension: collisionExtension,
        in: job.destinationDirectory
      )
    } else {
      target = plannedTarget
    }
    if target != plannedTarget { reservedPaths.remove(plannedTarget.path) }
    reservedPaths.insert(target.path)
    installingURLs[job.id] = target
    let targetForInstall = target
    let verifiedForInstall = validated
    let originalDestinationPath = plannedTarget.path
    let jobID = job.id
    do {
      let installedURL = try await Task.detached(priority: .utility) {
        try DownloadIntegrityVerifier.install(verifiedForInstall, at: targetForInstall)
      }.value
      installingURLs.removeValue(forKey: jobID)
      return installedURL
    } catch {
      installingURLs.removeValue(forKey: jobID)
      if targetForInstall.path != originalDestinationPath {
        reservedPaths.remove(targetForInstall.path)
      }
      throw error
    }
  }

  func finalPackageURL(for job: PersistedDownload) throws -> URL {
    guard job.verifiedPackage == true, let packageURL = job.destinationURL,
      FileManager.default.fileExists(atPath: packageURL.path)
    else {
      throw DownloadCoordinatorError.downloadUnavailable(
        LocalizedMessage("error.download.verifiedArchiveUnavailable")
      )
    }
    return packageURL
  }
}
