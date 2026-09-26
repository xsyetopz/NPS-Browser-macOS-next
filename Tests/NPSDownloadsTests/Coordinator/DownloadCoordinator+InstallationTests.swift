import Foundation
import Testing
@testable import NPSDownloads

extension DownloadCoordinatorTests {
  @Test("an existing file at a planned destination is not treated as verified")
  func destinationExistenceDoesNotProveIntegrity() async throws {
    let server = try FixtureHTTPServer { _ in
      FixtureHTTPResponse(status: 503, body: Data("failed response".utf8))
    }
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
        sourceURL: server.baseURL.appendingPathComponent("bad"),
        title: "Unverified",
        consoleType: "PSV",
        extractAfterDownload: true
      )
    )
    let failed = try await waitForTerminal(coordinator, id: queued.id)
    let destination = try #require(failed.destinationURL)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("not a verified package".utf8).write(to: destination)

    let current = try #require(await coordinator.snapshots().first { $0.id == queued.id })
    #expect(FileManager.default.fileExists(atPath: destination.path))
    #expect(current.hasVerifiedPackage == false)
    #expect(current.completedURL == nil)
    do {
      try await coordinator.retryExtraction(queued.id)
      Issue.record("retry extraction accepted a file that never passed integrity validation")
    } catch let error as DownloadCoordinatorError {
      #expect(error.localizedDescription.contains("Cannot change"))
    }
  }

  @Test("fails visibly when the configured destination disappears before installation")
  func unavailableDestinationDoesNotGetRecreated() async throws {
    let pkg = makePKGFixture(repetitions: 4)
    let server = try FixtureHTTPServer { _ in
      var response = FixtureHTTPResponse(body: pkg)
      response.chunkSize = 256
      response.chunkDelayMicroseconds = 20_000
      return response
    }
    let workspace = try makeTemporaryDirectory()
    let library = workspace.appendingPathComponent("ExternalLibrary", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }
    let coordinator = try makeCoordinator(
      destination: library,
      persistence: workspace.appendingPathComponent("jobs.plist")
    )
    let queued = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("volume-removal"),
        title: "External",
        consoleType: "PSV"
      )
    )
    try FileManager.default.removeItem(at: library)
    let result = try await waitForTerminal(coordinator, id: queued.id)
    #expect(result.state == .failed)
    #expect(result.errorMessage?.contains("external volume may be disconnected") == true)
    #expect(!FileManager.default.fileExists(atPath: library.path))
  }
}
