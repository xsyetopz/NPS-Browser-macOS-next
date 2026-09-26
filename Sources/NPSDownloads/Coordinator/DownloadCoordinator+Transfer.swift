import Foundation
import NPSCore

extension DownloadCoordinator {
  func perform(_ id: UUID) async {
    defer { finish(id) }
    guard let startingJob = jobs[id] else { return }
    // A pause can race queue reservation and URLSession task creation.
    guard startingJob.state == .downloading else { return }

    var installedURL: URL?
    var installedArtifact: PersistedTransferArtifact?
    var artifact = startingJob.activeTransfer ?? .primary
    do {
      while true {
        guard let activeJob = jobs[id] else { return }
        let sourceURL: URL
        switch artifact {
        case .primary: sourceURL = activeJob.request.sourceURL
        case .compatibilityPatch:
          guard let patchURL = activeJob.request.compatibilityPatchURL else {
            throw DownloadCoordinatorError.invalidRequest(
              LocalizedMessage("error.download.missingPatchURL")
            )
          }
          sourceURL = patchURL
        }

        let completion = try await transferClient.download(
          id: id,
          sourceURL: sourceURL,
          resumeData: activeJob.resumeData
        ) { [weak self] received, expected in
          guard let self else { return }
          Task { await self.reportProgress(id: id, received: received, expected: expected) }
        }
        stagingURLs[id] = completion.temporaryURL
        guard var job = jobs[id] else {
          try? FileManager.default.removeItem(at: completion.temporaryURL)
          stagingURLs.removeValue(forKey: id)
          return
        }

        job.state = .verifying
        job.progress = max(job.progress, 0.99)
        job.setError(nil)
        job.resumeData = nil
        job.updatedAt = Date()
        try commit(job)
        publish()

        let validationRequest = try requestForValidation(job.request, artifact: artifact)
        let validated = try await Task.detached(priority: .utility) {
          try DownloadIntegrityVerifier.validate(completion, for: validationRequest)
        }.value
        if let afterValidation { await afterValidation(id) }
        guard jobs[id] != nil else {
          try? FileManager.default.removeItem(at: completion.temporaryURL)
          stagingURLs.removeValue(forKey: id)
          return
        }

        let finalURL = try await install(validated, for: job, artifact: artifact)
        installedURL = finalURL
        installedArtifact = artifact
        stagingURLs.removeValue(forKey: id)
        guard var current = jobs[id] else {
          try? FileManager.default.removeItem(at: finalURL)
          reservedPaths.remove(finalURL.path)
          return
        }

        switch artifact {
        case .primary:
          current.destinationURL = finalURL
          current.verifiedPackage = true
        case .compatibilityPatch:
          current.compatibilityPatchDestinationURL = finalURL
          current.compatibilityPatchVerified = true
        }
        current.resumeData = nil
        current.progress = 1
        current.updatedAt = Date()

        if artifact == .primary, current.request.compatibilityPatchURL != nil {
          current.activeTransfer = .compatibilityPatch
          current.progress = 0
          current.bytesReceived = 0
          current.setError(nil)
          if isDrainingForShutdown {
            // Quit is waiting on this job. Keep the verified pack and queue the
            // patch transfer for the next launch instead of starting it now.
            current.state = .queued
            try commit(current)
            publish()
            return
          }
          current.state = .downloading
          try commit(current)
          publish()
          artifact = .compatibilityPatch
          continue
        }

        if current.request.extractAfterDownload {
          current.state = .extracting
          try commit(current)
          publish()

          let extracted: URL
          if current.request.fileExtension.lowercased() == "ppk" {
            guard let titleID = current.request.titleID else {
              throw DownloadCoordinatorError.invalidRequest(
                LocalizedMessage("error.download.extractionRequiresTitleID")
              )
            }
            let packageURL = try finalPackageURL(for: current)
            if current.request.compatibilityPatchMode == .overlayExistingOutput {
              guard current.request.compatibilityPatchURL == nil else {
                throw DownloadCoordinatorError.invalidRequest(
                  LocalizedMessage("error.download.overlayWithPatchURL")
                )
              }
              extracted = try await CompatibilityPackExtractor().applyPatch(
                patchURL: packageURL,
                titleID: titleID,
                destinationDirectory: current.destinationDirectory
              )
            } else if current.request.compatibilityPatchURL != nil {
              guard current.compatibilityPatchVerified == true,
                let patchPackage = current.compatibilityPatchDestinationURL
              else {
                throw DownloadCoordinatorError.downloadUnavailable(
                  LocalizedMessage("error.download.patchNotVerified")
                )
              }
              extracted = try await CompatibilityPackExtractor().extract(
                packURL: packageURL,
                patchURL: patchPackage,
                titleID: titleID,
                destinationDirectory: current.destinationDirectory
              )
            } else {
              extracted = try await CompatibilityPackExtractor().extract(
                packURL: packageURL,
                patchURL: nil,
                titleID: titleID,
                destinationDirectory: current.destinationDirectory
              )
            }
          } else {
            guard let extractor else {
              throw DownloadCoordinatorError.downloadUnavailable(
                LocalizedMessage("error.download.verifiedWithoutExtractor")
              )
            }
            extracted = try await extractor.extract(
              packageURL: try finalPackageURL(for: current),
              request: current.request,
              destinationDirectory: current.destinationDirectory
            )
          }
          guard jobs[id] != nil else {
            try? FileManager.default.removeItem(at: extracted)
            return
          }
          try completeExtraction(id, extractedDirectoryURL: extracted)
        } else {
          current.state = .complete
          current.setError(nil)
          try commit(current)
        }
        publish()
        return
      }
    } catch {
      if let stagingURL = stagingURLs.removeValue(forKey: id) {
        try? FileManager.default.removeItem(at: stagingURL)
      }
      if let installedURL, let installedArtifact, let job = jobs[id] {
        let wasRecorded =
          installedArtifact == .primary
          ? job.verifiedPackage == true : job.compatibilityPatchVerified == true
        if !wasRecorded {
          try? FileManager.default.removeItem(at: installedURL)
          let recordedURL =
            installedArtifact == .primary
            ? job.destinationURL : job.compatibilityPatchDestinationURL
          if recordedURL?.path != installedURL.path { reservedPaths.remove(installedURL.path) }
        }
      }
      if isPersistenceFailure(error) {
        publish()
        return
      }
      guard var job = jobs[id] else { return }
      if job.state == .paused {
        let resumeData = (error as? TransferFailure)?.resumeData
        if let resumeData {
          job.resumeData = resumeData
          job.setError(nil)
        } else if job.bytesReceived == 0, deferredResumes.contains(id) {
          job.resumeData = nil
          job.setError(nil)
        } else {
          job.state = .failed
          job.resumeData = nil
          job.setError(DownloadCoordinatorError.invalidResumeData.localizedMessage)
        }
      } else if job.state != .complete {
        let wasDownloading = job.state == .downloading
        if let resumeData = (error as? TransferFailure)?.resumeData, wasDownloading {
          job.state = .paused
          job.resumeData = resumeData
          job.setError(LocalizedMessage("error.download.interruptedWithResume"))
        } else {
          job.state = .failed
          if error is TransferFailure, wasDownloading {
            job.setError(
              LocalizedMessage(
                "error.download.interruptedWithoutResume",
                .message(LocalizedMessage(error))
              )
            )
          } else {
            job.setError(LocalizedMessage(error))
          }
        }
      }
      job.updatedAt = Date()
      do { try commit(job) } catch {}
      publish()
    }
  }

  private func requestForValidation(
    _ request: DownloadJobRequest,
    artifact: PersistedTransferArtifact
  ) throws -> DownloadJobRequest {
    switch artifact {
    case .primary: return request
    case .compatibilityPatch:
      guard let patchURL = request.compatibilityPatchURL else {
        throw DownloadCoordinatorError.invalidRequest(
          LocalizedMessage("error.download.missingPatchURL")
        )
      }
      return DownloadJobRequest(
        sourceURL: patchURL,
        title: "\(request.title) CPatch",
        consoleType: "PSV",
        titleID: request.titleID,
        fileExtension: "ppk"
      )
    }
  }

  private func reportProgress(id: UUID, received: Int64, expected: Int64) {
    guard var job = jobs[id], job.state == .downloading else { return }
    job.bytesReceived = received
    if expected > 0 { job.progress = min(0.99, max(0, Double(received) / Double(expected))) }
    job.updatedAt = Date()
    jobs[id] = job
    publish()
  }
}
