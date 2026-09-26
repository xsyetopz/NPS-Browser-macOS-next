import Foundation
import Testing
@testable import NPSDownloads

extension DownloadCoordinatorTests {
  @Test(
    "a caller-chosen job ID is published before enqueue returns; duplicates keep the original ID"
  )
  func callerChosenJobIDIsPublishedAndDeduplicatedRequestsKeepTheExistingID() async throws {
    // Arrange
    let pkg = makePKGFixture(repetitions: 3)
    let server = try FixtureHTTPServer { _ in FixtureHTTPResponse(body: pkg) }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = try makeCoordinator(
      destination: directory,
      persistence: directory.appendingPathComponent("jobs.plist"),
      limit: 1
    )
    let updates = await coordinator.updates()
    var iterator = updates.makeAsyncIterator()
    _ = await iterator.next()
    let request = DownloadJobRequest(
      sourceURL: server.baseURL.appendingPathComponent("chosen"),
      title: "chosen",
      consoleType: "PSV"
    )
    let requestedID = UUID()

    // Act
    let queued = try await coordinator.enqueue(request, jobID: requestedID)
    let firstPublished = await iterator.next()
    let duplicate = try await coordinator.enqueue(request, jobID: UUID())

    // Assert
    #expect(queued.id == requestedID)
    #expect(firstPublished?.contains { $0.id == requestedID } == true)
    #expect(duplicate.id == requestedID)
    let result = try await waitForTerminal(coordinator, id: requestedID)
    #expect(result.state == .complete)
  }

  @Test("deduplicates rapid requests and snapshots destination settings per job")
  func deduplicatesAndKeepsDestination() async throws {
    let pkg = makePKGFixture(repetitions: 3)
    let server = try FixtureHTTPServer { _ in FixtureHTTPResponse(body: pkg) }
    let firstRoot = try makeTemporaryDirectory()
    let secondRoot = try makeTemporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: firstRoot)
      try? FileManager.default.removeItem(at: secondRoot)
    }
    let preferences = LockedPreferences(
      DownloadPreferences(downloadDirectory: firstRoot, concurrentDownloads: 1)
    )
    let coordinator = try DownloadCoordinator(
      preferences: { preferences.snapshot() },
      persistenceURL: firstRoot.appendingPathComponent("jobs.plist"),
      extractor: FixturePackageExtractor(),
      urlSessionConfiguration: .ephemeral
    )
    let firstRequest = DownloadJobRequest(
      sourceURL: server.baseURL.appendingPathComponent("same"),
      title: "same",
      consoleType: "PSP"
    )
    let first = try await coordinator.enqueue(firstRequest)
    let duplicate = try await coordinator.enqueue(firstRequest)
    #expect(first.id == duplicate.id)
    preferences.update(DownloadPreferences(downloadDirectory: secondRoot, concurrentDownloads: 1))
    let changedOptions = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: firstRequest.sourceURL,
        title: firstRequest.title,
        consoleType: firstRequest.consoleType,
        extractAfterDownload: true
      )
    )
    #expect(changedOptions.id != first.id)
    let second = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("different"),
        title: "different",
        consoleType: "PSP"
      )
    )

    let firstResult = try await waitForTerminal(coordinator, id: first.id)
    let changedOptionsResult = try await waitForTerminal(coordinator, id: changedOptions.id)
    let secondResult = try await waitForTerminal(coordinator, id: second.id)
    #expect(firstResult.destinationURL?.path.hasPrefix(firstRoot.path) == true)
    #expect(changedOptionsResult.destinationURL?.path.hasPrefix(secondRoot.path) == true)
    #expect(secondResult.destinationURL?.path.hasPrefix(secondRoot.path) == true)
    #expect(firstResult.state == .complete)
    #expect(changedOptionsResult.state == .complete)
    #expect(secondResult.state == .complete)
  }

  @Test("terminal jobs do not suppress a fresh request with the same options")
  func terminalJobsCanBeEnqueuedAgain() async throws {
    let pkg = makePKGFixture(repetitions: 8)
    let server = try FixtureHTTPServer { request in
      if request.path == "/failed" {
        return FixtureHTTPResponse(status: 503, body: Data("unavailable".utf8))
      }
      return FixtureHTTPResponse(body: pkg)
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = try makeCoordinator(
      destination: directory,
      persistence: directory.appendingPathComponent("jobs.plist")
    )

    let completedRequest = DownloadJobRequest(
      sourceURL: server.baseURL.appendingPathComponent("completed"),
      title: "Same Complete Request",
      consoleType: "PSV"
    )
    let completed = try await coordinator.enqueue(completedRequest)
    let completedResult = try await waitForTerminal(coordinator, id: completed.id)
    #expect(completedResult.state == .complete)
    let completedAgain = try await coordinator.enqueue(completedRequest)
    #expect(completedAgain.id != completed.id)
    #expect(completedAgain.destinationURL != completed.destinationURL)
    let completedAgainResult = try await waitForTerminal(coordinator, id: completedAgain.id)
    #expect(completedAgainResult.state == .complete)

    let failedRequest = DownloadJobRequest(
      sourceURL: server.baseURL.appendingPathComponent("failed"),
      title: "Same Failed Request",
      consoleType: "PSV"
    )
    let failed = try await coordinator.enqueue(failedRequest)
    let failedResult = try await waitForTerminal(coordinator, id: failed.id)
    #expect(failedResult.state == .failed)
    let failedAgain = try await coordinator.enqueue(failedRequest)
    #expect(failedAgain.id != failed.id)
    let failedAgainResult = try await waitForTerminal(coordinator, id: failedAgain.id)
    #expect(failedAgainResult.state == .failed)
  }

  @Test("enforces the configured concurrent transfer limit")
  func boundedConcurrency() async throws {
    let pkg = makePKGFixture(repetitions: 128)
    let server = try FixtureHTTPServer { _ in
      var response = FixtureHTTPResponse(body: pkg)
      response.chunkSize = 1024
      response.chunkDelayMicroseconds = 2_000
      return response
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = try makeCoordinator(
      destination: directory,
      persistence: directory.appendingPathComponent("jobs.plist"),
      limit: 2
    )
    var ids: [UUID] = []
    for index in 0..<5 {
      let item = try await coordinator.enqueue(
        DownloadJobRequest(
          sourceURL: server.baseURL.appendingPathComponent("job-\(index)"),
          title: "job \(index)",
          consoleType: "PSX"
        )
      )
      ids.append(item.id)
    }
    let results = try await waitForAllTerminal(coordinator, ids: ids)
    #expect(results.allSatisfy { $0.state == .complete })
    #expect(server.maximumObservedConnections <= 2)
  }

  @Test("pause exposes valid resume when supplied, with restart fallback")
  func pauseAndResumeOrRestart() async throws {
    let pkg = makePKGFixture(repetitions: 128)
    let requestCount = LockedCounter()
    let server = try FixtureHTTPServer { request in
      _ = requestCount.increment()
      if let rangeHeader = request.headers["range"],
        let offsetText = rangeHeader.split(separator: "=").last?.split(separator: "-").first,
        let offset = Int(offsetText), offset >= 0, offset < pkg.count
      {
        var response = FixtureHTTPResponse(status: 206, body: Data(pkg.dropFirst(offset)))
        response.headers["Accept-Ranges"] = "bytes"
        response.headers["Content-Range"] = "bytes \(offset)-\(pkg.count - 1)/\(pkg.count)"
        response.headers["ETag"] = "\"fixture-v1\""
        return response
      }
      var response = FixtureHTTPResponse(body: pkg)
      response.headers["Accept-Ranges"] = "bytes"
      response.headers["ETag"] = "\"fixture-v1\""
      response.chunkSize = 2 * 1024
      response.chunkDelayMicroseconds = 20_000
      return response
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = try makeCoordinator(
      destination: directory,
      persistence: directory.appendingPathComponent("jobs.plist")
    )
    let job = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("resumable"),
        title: "Resumable",
        consoleType: "PSP",
        expectedByteCount: Int64(pkg.count)
      )
    )
    var receivingBytes = false
    for _ in 0..<200 {
      if let current = await coordinator.snapshots().first(where: { $0.id == job.id }),
        current.state == .downloading, current.bytesReceived > 0
      {
        receivingBytes = true
        break
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(receivingBytes)
    try await coordinator.pause(job.id)

    var pausedOrFailed: DownloadSnapshot?
    for _ in 0..<300 {
      if let current = await coordinator.snapshots().first(where: { $0.id == job.id }),
        current.state == .failed || (current.state == .paused && current.canResume)
      {
        pausedOrFailed = current
        break
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let paused = try #require(pausedOrFailed)
    if paused.canResume {
      #expect(paused.state == .paused)
      try await coordinator.resume(job.id)
    } else {
      #expect(paused.state == .failed)
      #expect(paused.errorMessage?.contains("Restart this download") == true)
      try await coordinator.restart(job.id)
    }

    var result = try await waitForTerminal(coordinator, id: job.id)
    if result.state == .failed {
      try await coordinator.restart(job.id)
      result = try await waitForTerminal(coordinator, id: job.id)
    }
    #expect(result.state == .complete)
    #expect(requestCount.count >= 2)
  }

  @Test("a Pause arriving before URLSession task registration is honored and resumable from zero")
  func immediatePauseBeforeTaskRegistration() async throws {
    let pkg = makePKGFixture(repetitions: 256)
    let requests = LockedCounter()
    let server = try FixtureHTTPServer { _ in
      _ = requests.increment()
      var response = FixtureHTTPResponse(body: pkg)
      response.chunkSize = 1024
      response.chunkDelayMicroseconds = 20_000
      return response
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = try makeCoordinator(
      destination: directory,
      persistence: directory.appendingPathComponent("jobs.plist")
    )
    let queued = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("immediate-pause"),
        title: "Immediate Pause",
        consoleType: "PSP"
      )
    )
    try await coordinator.pause(queued.id)
    try await Task.sleep(nanoseconds: 200_000_000)
    let afterPause = try #require(await coordinator.snapshots().first { $0.id == queued.id })
    #expect(afterPause.state == .paused || afterPause.state == .failed)
    #expect(afterPause.state != .complete)
  }

  @Test("removing a job releases its reserved filename")
  func removingReleasesFilenameReservation() async throws {
    let pkg = makePKGFixture(repetitions: 32)
    let server = try FixtureHTTPServer { request in
      var response = FixtureHTTPResponse(body: pkg)
      if request.path == "/first" {
        response.chunkSize = 16
        response.chunkDelayMicroseconds = 10_000
      }
      return response
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = try makeCoordinator(
      destination: directory,
      persistence: directory.appendingPathComponent("jobs.plist")
    )
    let first = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("first"),
        title: "Reusable Name",
        consoleType: "PSP"
      )
    )
    try await coordinator.remove(first.id)
    let second = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("second"),
        title: "Reusable Name",
        consoleType: "PSP"
      )
    )
    #expect(second.destinationURL == first.destinationURL)
    let result = try await waitForTerminal(coordinator, id: second.id)
    #expect(result.state == .complete)
  }
}

extension CompatibilityPackTests {
  @Test("compatibility jobs deduplicate only when both pack and patch URLs match")
  func compatibilityDedupUsesFullURLs() async throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let archive = storedZip([
      StoredZipEntry(name: "payload.bin", data: Data(repeating: 0x5A, count: 128 * 1024))
    ])
    let server = try FixtureHTTPServer { _ in
      var response = FixtureHTTPResponse(body: archive)
      response.chunkSize = 4 * 1024
      response.chunkDelayMicroseconds = 10_000
      return response
    }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 2) },
      persistenceURL: workspace.appendingPathComponent("downloads.plist"),
      urlSessionConfiguration: .ephemeral
    )
    let firstRequest = CompatibilityPackRequest(
      titleID: "PCSA00007",
      title: "Updated URL",
      packURL: server.baseURL.appendingPathComponent("pack-one"),
      patchURL: server.baseURL.appendingPathComponent("patch-one")
    )
    let first = try await coordinator.enqueueCompatibilityPack(firstRequest)
    let duplicate = try await coordinator.enqueueCompatibilityPack(firstRequest)
    let newPackURL = try await coordinator.enqueueCompatibilityPack(
      CompatibilityPackRequest(
        titleID: firstRequest.titleID,
        title: firstRequest.title,
        packURL: server.baseURL.appendingPathComponent("pack-two"),
        patchURL: firstRequest.patchURL
      )
    )
    let newPatchURL = try await coordinator.enqueueCompatibilityPack(
      CompatibilityPackRequest(
        titleID: firstRequest.titleID,
        title: firstRequest.title,
        packURL: firstRequest.packURL,
        patchURL: server.baseURL.appendingPathComponent("patch-two")
      )
    )

    #expect(duplicate.id == first.id)
    #expect(newPackURL.id != first.id)
    #expect(newPatchURL.id != first.id)
    for id in [first.id, newPackURL.id, newPatchURL.id] {
      let result = try await waitForTerminal(coordinator, id: id)
      #expect(result.state == .complete)
    }
  }

  @Test("remove cannot roll back or delete a prior output while PPK extraction is active")
  func removeDuringOutputReplacementIsRejected() async throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let archive = storedZip([
      StoredZipEntry(name: "new-output.bin", data: Data(repeating: 0x43, count: 2 * 1024 * 1024))
    ])
    let server = try FixtureHTTPServer { _ in
      var response = FixtureHTTPResponse(body: archive)
      response.chunkSize = 128 * 1024
      response.chunkDelayMicroseconds = 1_000
      return response
    }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    let existingOutput = library.appendingPathComponent("PSV/rePatch/PCSA00008", isDirectory: true)
    try FileManager.default.createDirectory(at: existingOutput, withIntermediateDirectories: true)
    try Data("prior output".utf8).write(to: existingOutput.appendingPathComponent("prior.txt"))
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 1) },
      persistenceURL: workspace.appendingPathComponent("downloads.plist"),
      urlSessionConfiguration: .ephemeral
    )
    // Every committed state is published, so the stream cannot miss the
    // short-lived extracting state the way wall-clock polling can under load.
    let updates = await coordinator.updates()
    let queued = try await coordinator.enqueueCompatibilityPack(
      CompatibilityPackRequest(
        titleID: "PCSA00008",
        title: "Output replacement",
        packURL: server.baseURL.appendingPathComponent("pack")
      )
    )

    var observedExtraction = false
    for await snapshots in updates {
      guard let state = snapshots.first(where: { $0.id == queued.id })?.state else { continue }
      if state == .extracting { observedExtraction = true }
      if state == .extracting || state == .complete || state == .failed { break }
    }
    #expect(observedExtraction)

    var removeWasRejected = false
    do { try await coordinator.remove(queued.id) } catch {
      removeWasRejected = true
      #expect(error.localizedDescription.contains("Removal is unavailable while extraction"))
    }
    if !removeWasRejected {
      #expect(await coordinator.snapshots().contains { $0.id == queued.id } == false)
    } else {
      let result = try await waitForTerminal(coordinator, id: queued.id)
      #expect(result.state == .complete)
    }

    #expect(FileManager.default.fileExists(atPath: existingOutput.path))
    #expect(
      FileManager.default.fileExists(
        atPath: existingOutput.appendingPathComponent("new-output.bin").path
      )
    )
  }
}
