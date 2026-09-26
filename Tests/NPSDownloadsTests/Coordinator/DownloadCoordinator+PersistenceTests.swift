import Foundation
import Testing
@testable import NPSDownloads

extension DownloadCoordinatorTests {
  @Test("a persistence failure rolls back enqueue and prevents starting the transfer")
  func enqueuePersistenceFailureIsTransactional() async throws {
    let requestCount = LockedCounter()
    let server = try FixtureHTTPServer { _ in
      _ = requestCount.increment()
      return FixtureHTTPResponse(body: makePKGFixture(repetitions: 4))
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = directory.appendingPathComponent("jobs.plist")
    let coordinator = try makeCoordinator(destination: directory, persistence: persistence)
    try FileManager.default.removeItem(at: persistence)
    try FileManager.default.createDirectory(at: persistence, withIntermediateDirectories: false)

    do {
      _ = try await coordinator.enqueue(
        DownloadJobRequest(
          sourceURL: server.baseURL.appendingPathComponent("must-not-start"),
          title: "Unwritable Queue",
          consoleType: "PSV"
        )
      )
      Issue.record("enqueue succeeded although its queue state could not be saved")
    } catch {
      #expect(error.localizedDescription.contains("queue could not be saved"))
      #expect(error.localizedDescription.contains("write permissions"))
    }

    #expect(await coordinator.snapshots().isEmpty)
    #expect(requestCount.isEmpty)
  }
}
