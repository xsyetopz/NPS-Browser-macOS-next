import Foundation
import Testing
@testable import NPSDownloads

private struct PauseAllCallSnapshot: Sendable {
  let completed: Bool
  let errorMessage: String?
}

private actor PauseAllCallResult {
  private var current = PauseAllCallSnapshot(completed: false, errorMessage: nil)

  func finish(errorMessage: String?) {
    current = PauseAllCallSnapshot(completed: true, errorMessage: errorMessage)
  }

  func snapshot() -> PauseAllCallSnapshot { current }
}

@Suite(.sourceEnglish)
struct DownloadCoordinatorTests {
  @Test("shutdown pauses active work without starting queued jobs")
  func pauseAllDoesNotStartQueuedJobsDuringShutdown() async throws {
    let activeRequests = LockedCounter()
    let queuedRequests = LockedCounter()
    let stalledPackage = makePKGFixture(repetitions: 8_192)
    let queuedPackage = makePKGFixture(repetitions: 8)
    let server = try FixtureHTTPServer { request in
      if request.path == "/active" {
        _ = activeRequests.increment()
        var response = FixtureHTTPResponse(body: stalledPackage)
        response.chunkSize = 1_024
        response.chunkDelayMicroseconds = 2_000
        return response
      }
      _ = queuedRequests.increment()
      return FixtureHTTPResponse(body: queuedPackage)
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = directory.appendingPathComponent("jobs.plist")
    let coordinator = try makeCoordinator(
      destination: directory,
      persistence: persistence,
      limit: 1
    )

    let active = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("active"),
        title: "Active transfer",
        consoleType: "PSV",
        expectedByteCount: Int64(stalledPackage.count)
      )
    )
    for _ in 0..<200 {
      if !activeRequests.isEmpty { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(activeRequests.count == 1)

    let queued = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("queued"),
        title: "Queued transfer",
        consoleType: "PSV",
        expectedByteCount: Int64(queuedPackage.count)
      )
    )
    #expect(queued.state == .queued)
    #expect(queuedRequests.isEmpty)

    let start = Date()
    try await coordinator.pauseAll()
    let elapsed = Date().timeIntervalSince(start)
    #expect(elapsed < 5)

    let afterDrain = await coordinator.snapshots()
    let activeAfterDrain = try #require(afterDrain.first { $0.id == active.id })
    let queuedAfterDrain = try #require(afterDrain.first { $0.id == queued.id })
    #expect(activeAfterDrain.state == .paused || activeAfterDrain.state == .failed)
    #expect(queuedAfterDrain.state == .queued)
    #expect(queuedRequests.isEmpty)

    let restored = try makeCoordinator(destination: directory, persistence: persistence, limit: 1)
    let resumedQueue = try await waitForTerminal(restored, id: queued.id)
    #expect(resumedQueue.state == .complete)
    #expect(queuedRequests.count == 1)
  }

  @Test("pause-all reports queue persistence failure without cancelling active work")
  func pauseAllPersistenceFailureReturnsPromptlyAndPreservesTransfer() async throws {
    let activeRequests = LockedCounter()
    let stalledPackage = makePKGFixture(repetitions: 4_096)
    let server = try FixtureHTTPServer { _ in
      _ = activeRequests.increment()
      var response = FixtureHTTPResponse(body: stalledPackage)
      response.chunkSize = 1_024
      response.chunkDelayMicroseconds = 20_000
      return response
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = directory.appendingPathComponent("jobs.plist")
    let coordinator = try makeCoordinator(destination: directory, persistence: persistence)
    let active = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("active"),
        title: "Active transfer",
        consoleType: "PSV",
        expectedByteCount: Int64(stalledPackage.count)
      )
    )
    for _ in 0..<200 {
      if !activeRequests.isEmpty { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(activeRequests.count == 1)

    let originalQueue = try Data(contentsOf: persistence)
    try FileManager.default.removeItem(at: persistence)
    try FileManager.default.createDirectory(at: persistence, withIntermediateDirectories: false)

    let result = PauseAllCallResult()
    let drainTask = Task {
      do {
        try await coordinator.pauseAll()
        await result.finish(errorMessage: nil)
      } catch { await result.finish(errorMessage: error.localizedDescription) }
    }
    let started = Date()
    var outcome = await result.snapshot()
    for _ in 0..<100 where !outcome.completed {
      try await Task.sleep(nanoseconds: 10_000_000)
      outcome = await result.snapshot()
    }
    #expect(outcome.completed)
    #expect(
      outcome.errorMessage?.localizedCaseInsensitiveContains("queue could not be saved") == true
    )
    #expect(Date().timeIntervalSince(started) < 2)
    let activeAfterFailure = try #require(
      await coordinator.snapshots().first { $0.id == active.id }
    )
    #expect(activeAfterFailure.state == .downloading)
    #expect(activeRequests.count == 1)

    // Restore this test's temporary queue and drain the still-running task
    // after the assertions, including when a regression misses the deadline.
    try FileManager.default.removeItem(at: persistence)
    try originalQueue.write(to: persistence, options: .atomic)
    try await coordinator.pauseAll()
    await drainTask.value
  }

  @Test("restored transfers without valid resume data require a full restart")
  func restoredTransferRequiresRestartWhenResumeUnavailable() async throws {
    let pkg = makePKGFixture(repetitions: 16)
    let server = try FixtureHTTPServer { _ in FixtureHTTPResponse(body: pkg) }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistenceURL = directory.appendingPathComponent("jobs.plist")
    let request = DownloadJobRequest(
      sourceURL: server.baseURL.appendingPathComponent("restored"),
      title: "Restored",
      consoleType: "PSP"
    )
    let now = Date()
    let id = UUID()
    let queuedID = UUID()
    let queuedRequest = DownloadJobRequest(
      sourceURL: server.baseURL.appendingPathComponent("already-queued"),
      title: "Already Queued",
      consoleType: "PSP"
    )
    let destination = directory.appendingPathComponent("PSP", isDirectory: true)
      .appendingPathComponent("Restored.pkg")
    let queuedDestination = directory.appendingPathComponent("PSP", isDirectory: true)
      .appendingPathComponent("Already Queued.pkg")
    try DownloadStore(fileURL: persistenceURL).save([
      PersistedDownload(
        id: id,
        request: request,
        state: .downloading,
        progress: 0.25,
        bytesReceived: 100,
        destinationDirectory: destination.deletingLastPathComponent(),
        destinationVolumeUUID: nil,
        destinationURL: destination,
        extractedDirectoryURL: nil,
        errorMessage: nil,
        resumeData: nil,
        createdAt: now,
        updatedAt: now
      ),
      PersistedDownload(
        id: queuedID,
        request: queuedRequest,
        state: .queued,
        progress: 0,
        bytesReceived: 0,
        destinationDirectory: queuedDestination.deletingLastPathComponent(),
        destinationVolumeUUID: nil,
        destinationURL: queuedDestination,
        extractedDirectoryURL: nil,
        errorMessage: nil,
        resumeData: nil,
        createdAt: now.addingTimeInterval(1),
        updatedAt: now
      ),
    ])
    let coordinator = try makeCoordinator(destination: directory, persistence: persistenceURL)
    let restored = try #require(await coordinator.snapshots().first { $0.id == id })
    #expect(restored.id == id)
    #expect(restored.state == .failed)
    #expect(restored.canRestart)
    #expect(restored.errorMessage?.contains("Restart this download") == true)

    let restoredQueueResult = try await waitForTerminal(coordinator, id: queuedID)
    #expect(restoredQueueResult.state == .complete)
    try await coordinator.restart(id)
    let result = try await waitForTerminal(coordinator, id: id)
    #expect(result.state == .complete)
  }
}

extension CompatibilityPackTests {
  @Test(
    "restored compatibility jobs resume the recorded patch stage instead of redownloading the pack"
  )
  func restoredPatchStage() async throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let pack = try createZipArchive(
      at: workspace.appendingPathComponent("pack.zip"),
      files: ["content/base.txt": "base"]
    )
    let patch = try createZipArchive(
      at: workspace.appendingPathComponent("patch.zip"),
      files: ["content/update.txt": "patch"]
    )
    let log = CompatibilityRequestLog()
    let server = try FixtureHTTPServer { request in
      log.append(request.path)
      return FixtureHTTPResponse(body: patch)
    }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    let consoleDirectory = library.appendingPathComponent("PSV", isDirectory: true)
    try FileManager.default.createDirectory(at: consoleDirectory, withIntermediateDirectories: true)
    let packageURL = consoleDirectory.appendingPathComponent("Restored Pack.ppk")
    let patchURL = consoleDirectory.appendingPathComponent("Restored Pack CPatch.ppk")
    try pack.write(to: packageURL)
    let request = DownloadJobRequest(
      sourceURL: server.baseURL.appendingPathComponent("pack"),
      title: "Restored Pack",
      consoleType: "PSV",
      titleID: "PCSA00005",
      fileExtension: "ppk",
      extractAfterDownload: true,
      compatibilityPatchURL: server.baseURL.appendingPathComponent("patch")
    )
    let now = Date()
    let persisted = PersistedDownload(
      id: UUID(),
      request: request,
      state: .queued,
      progress: 0,
      bytesReceived: 0,
      destinationDirectory: consoleDirectory,
      destinationVolumeUUID: nil,
      destinationURL: packageURL,
      verifiedPackage: true,
      compatibilityPatchDestinationURL: patchURL,
      compatibilityPatchVerified: false,
      activeTransfer: .compatibilityPatch,
      extractedDirectoryURL: nil,
      errorMessage: nil,
      resumeData: nil,
      createdAt: now,
      updatedAt: now
    )
    let persistence = workspace.appendingPathComponent("downloads.plist")
    try DownloadStore(fileURL: persistence).save([persisted])
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 1) },
      persistenceURL: persistence,
      urlSessionConfiguration: .ephemeral
    )
    let result = try await waitForTerminal(coordinator, id: persisted.id)
    #expect(result.state == .complete)
    #expect(log.paths == ["/patch"])
    #expect(
      String(
        bytes: try Data(
          contentsOf: library.appendingPathComponent("PSV/rePatch/PCSA00005/content/update.txt")
        ),
        encoding: .utf8
      ) == "patch"
    )
  }
}
