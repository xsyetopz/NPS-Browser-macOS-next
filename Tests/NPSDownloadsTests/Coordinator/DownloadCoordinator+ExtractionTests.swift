import Foundation
import Testing
@testable import NPSDownloads

extension DownloadCoordinatorTests {
  @Test(
    "package cleanup happens only after successful extraction and reveal points to extracted output"
  )
  func packageCleanupAfterSuccessfulExtraction() async throws {
    let pkg = makePKGFixture(repetitions: 8)
    let server = try FixtureHTTPServer { _ in FixtureHTTPResponse(body: pkg) }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: directory, concurrentDownloads: 1) },
      persistenceURL: directory.appendingPathComponent("jobs.plist"),
      extractor: FixturePackageExtractor(),
      urlSessionConfiguration: .ephemeral
    )
    let queued = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("extract"),
        title: "Extracted Game",
        consoleType: "PSV",
        titleID: "PCSA00001",
        extractAfterDownload: true,
        extractionOptions: PackageExtractionOptions(keepPackage: false)
      )
    )
    let result = try await waitForTerminal(coordinator, id: queued.id)
    #expect(result.state == .complete)
    #expect(result.destinationURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true)
    #expect(
      result.extractedDirectoryURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
    )
    #expect(result.completedURL == result.extractedDirectoryURL)
    #expect(result.hasVerifiedPackage == false)
    let revealed = await coordinator.revealURL(for: queued.id)
    #expect(revealed == result.extractedDirectoryURL)
  }
}

extension CompatibilityPackTests {
  @Test("retry extraction holds the title output slot before a newer same-title job starts")
  func retrySerializesSameTitleOutput() async throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let archive = storedZip([
      StoredZipEntry(name: "new-output.bin", data: Data(repeating: 0x35, count: 16 * 1024 * 1024))
    ])
    let log = CompatibilityRequestLog()
    let server = try FixtureHTTPServer { request in
      log.append(request.path)
      return FixtureHTTPResponse(body: archive)
    }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    let repatch = library.appendingPathComponent("PSV/rePatch", isDirectory: true)
    let conflictingOutput = repatch.appendingPathComponent("PCSA00009")
    try FileManager.default.createDirectory(at: repatch, withIntermediateDirectories: true)
    try Data("not a directory yet".utf8).write(to: conflictingOutput)
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 2) },
      persistenceURL: workspace.appendingPathComponent("downloads.plist"),
      urlSessionConfiguration: .ephemeral
    )
    let firstRequest = CompatibilityPackRequest(
      titleID: "PCSA00009",
      title: "Retry serialization",
      packURL: server.baseURL.appendingPathComponent("pack-one")
    )
    let first = try await coordinator.enqueueCompatibilityPack(firstRequest)
    let initialFailure = try await waitForTerminal(coordinator, id: first.id)
    #expect(initialFailure.state == .failed)
    #expect(initialFailure.hasVerifiedPackage)

    try FileManager.default.removeItem(at: conflictingOutput)
    try FileManager.default.createDirectory(
      at: conflictingOutput,
      withIntermediateDirectories: false
    )
    let retryTask = Task { try await coordinator.retryExtraction(first.id) }
    var retrying = false
    for _ in 0..<500 {
      if await coordinator.snapshots().first(where: { $0.id == first.id })?.state == .extracting {
        retrying = true
        break
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(retrying)

    let second = try await coordinator.enqueueCompatibilityPack(
      CompatibilityPackRequest(
        titleID: firstRequest.titleID,
        title: firstRequest.title,
        packURL: server.baseURL.appendingPathComponent("pack-two")
      )
    )
    let secondSnapshot = try #require(await coordinator.snapshots().first { $0.id == second.id })
    #expect(secondSnapshot.state == .queued)
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(log.paths == ["/pack-one"])

    try await retryTask.value
    let retryResult = try #require(await coordinator.snapshots().first { $0.id == first.id })
    #expect(retryResult.state == .complete)
    let secondResult = try await waitForTerminal(coordinator, id: second.id)
    #expect(secondResult.state == .complete)
    #expect(log.paths == ["/pack-one", "/pack-two"])
    #expect(
      FileManager.default.fileExists(
        atPath: conflictingOutput.appendingPathComponent("new-output.bin").path
      )
    )
  }
}
