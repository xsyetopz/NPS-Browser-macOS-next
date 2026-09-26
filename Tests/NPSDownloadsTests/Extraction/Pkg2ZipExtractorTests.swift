import Foundation
import Testing
@testable import NPSDownloads

extension DownloadCoordinatorTests {
  @Test("pkg2zip output identifies the title and ID and retains a successful extraction package")
  func pkg2zipUsesContentIdentifyingOutputFolder() async throws {
    let package = makePKGFixture(repetitions: 8)
    let server = try FixtureHTTPServer { _ in FixtureHTTPResponse(body: package) }
    let workspace = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let helper = workspace.appendingPathComponent("pkg2zip-fixture")
    try Data("#!/bin/sh\nprintf '%s' 'fixture extracted content' > 'content.txt'\n".utf8).write(
      to: helper
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: workspace, concurrentDownloads: 1) },
      persistenceURL: workspace.appendingPathComponent("jobs.plist"),
      extractor: Pkg2ZipExtractor(executableURL: helper),
      urlSessionConfiguration: .ephemeral
    )
    let queued = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("success"),
        title: "Golden Game",
        consoleType: "PSV",
        titleID: "PCSA00077",
        extractAfterDownload: true,
        extractionOptions: PackageExtractionOptions(keepPackage: true)
      )
    )

    let result = try await waitForTerminal(coordinator, id: queued.id)
    let output = try #require(result.extractedDirectoryURL)
    let downloadedPackage = try #require(result.destinationURL)
    #expect(result.state == .complete)
    #expect(output.lastPathComponent == "Golden Game _PCSA00077_")
    #expect(
      try Data(contentsOf: output.appendingPathComponent("content.txt"))
        == Data("fixture extracted content".utf8)
    )
    #expect(try Data(contentsOf: downloadedPackage) == package)
    #expect(await coordinator.revealURL(for: queued.id) == output)
  }

  @Test("pkg2zip helper failure preserves the verified package for retry or diagnosis")
  func pkg2zipFailureRetainsVerifiedPackage() async throws {
    let package = makePKGFixture(repetitions: 8)
    let server = try FixtureHTTPServer { _ in FixtureHTTPResponse(body: package) }
    let workspace = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let helper = workspace.appendingPathComponent("pkg2zip-failing-fixture")
    try Data("#!/bin/sh\necho 'fixture helper failed' >&2\nexit 23\n".utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: workspace, concurrentDownloads: 1) },
      persistenceURL: workspace.appendingPathComponent("jobs.plist"),
      extractor: Pkg2ZipExtractor(executableURL: helper),
      urlSessionConfiguration: .ephemeral
    )
    let queued = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("failure"),
        title: "Broken Game",
        consoleType: "PSV",
        titleID: "PCSA00078",
        extractAfterDownload: true,
        extractionOptions: PackageExtractionOptions(keepPackage: false)
      )
    )

    let result = try await waitForTerminal(coordinator, id: queued.id)
    let downloadedPackage = try #require(result.destinationURL)
    #expect(result.state == .failed)
    #expect(result.hasVerifiedPackage)
    #expect(result.extractedDirectoryURL == nil)
    #expect(result.errorMessage?.contains("23") == true)
    #expect(result.errorMessage?.contains("fixture helper failed") == true)
    #expect(try Data(contentsOf: downloadedPackage) == package)
    #expect(await coordinator.revealURL(for: queued.id) == downloadedPackage)
  }

  @Test("reports unsupported PS3 extraction without deleting the package")
  func ps3ExtractionIsExplicitlyUnsupported() async throws {
    let pkg = makePKGFixture(repetitions: 8)
    let server = try FixtureHTTPServer { _ in FixtureHTTPResponse(body: pkg) }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let extractor = Pkg2ZipExtractor(
      executableURL: directory.appendingPathComponent("unused-helper")
    )
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: directory, concurrentDownloads: 1) },
      persistenceURL: directory.appendingPathComponent("jobs.plist"),
      extractor: extractor,
      urlSessionConfiguration: .ephemeral
    )
    let job = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("ps3"),
        title: "PS3 Package",
        consoleType: "PS3",
        extractAfterDownload: true
      )
    )
    let result = try await waitForTerminal(coordinator, id: job.id)
    #expect(result.state == .failed)
    #expect(result.destinationURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    #expect(result.errorMessage?.contains("does not support extracting PS3") == true)
    #expect(result.hasVerifiedPackage)
    let failedReveal = await coordinator.revealURL(for: job.id)
    #expect(failedReveal == result.destinationURL)
  }
}
