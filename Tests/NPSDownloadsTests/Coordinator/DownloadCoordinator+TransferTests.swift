import Foundation
import Testing
@testable import NPSDownloads

extension DownloadCoordinatorTests {
  @Test("follows redirects, verifies catalogue values and reveals the actual completed URL")
  func redirectAndVerification() async throws {
    let pkg = makePKGFixture(repetitions: 32)
    let digest = sha256(pkg)
    let server = try FixtureHTTPServer { request in
      if request.path == "/redirect" {
        var response = FixtureHTTPResponse(status: 302, body: Data())
        response.headers["Location"] = "/package"
        return response
      }
      return FixtureHTTPResponse(body: pkg)
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = try makeCoordinator(
      destination: directory,
      persistence: directory.appendingPathComponent("jobs.plist")
    )
    let request = DownloadJobRequest(
      sourceURL: server.baseURL.appendingPathComponent("redirect"),
      title: "A game: title/unsafe",
      consoleType: "PSV",
      titleID: "PCSA00000",
      expectedByteCount: Int64(pkg.count),
      sha256: digest
    )

    let queued = try await coordinator.enqueue(request)
    let result = try await waitForTerminal(coordinator, id: queued.id)
    #expect(result.state == .complete)
    #expect(result.destinationURL?.lastPathComponent == "A game_ title_unsafe.pkg")
    #expect(result.destinationURL?.path.contains("/PSV/") == true)
    #expect(result.destinationURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    let revealed = await coordinator.revealURL(for: queued.id)
    #expect(revealed == result.destinationURL)
    #expect(result.progress == 1)
  }

  @Test("an interrupted transfer fails visibly and restart begins a new request")
  func interruptedTransferCanRestart() async throws {
    let pkg = makePKGFixture(repetitions: 512)
    let requestCount = LockedCounter()
    let server = try FixtureHTTPServer { _ in
      if requestCount.increment() == 1 {
        var response = FixtureHTTPResponse(body: pkg)
        response.chunkSize = 8 * 1024
        response.interruptAfterBytes = pkg.count / 3
        return response
      }
      return FixtureHTTPResponse(body: pkg)
    }
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = try makeCoordinator(
      destination: directory,
      persistence: directory.appendingPathComponent("jobs.plist")
    )
    let job = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("interrupt"),
        title: "Interrupted",
        consoleType: "PSV",
        expectedByteCount: Int64(pkg.count)
      )
    )
    let interrupted = try await waitForTerminal(coordinator, id: job.id)
    #expect(interrupted.state == .failed)
    #expect(
      interrupted.destinationURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true
    )

    try await coordinator.restart(job.id)
    let restarted = try await waitForTerminal(coordinator, id: job.id)
    #expect(restarted.state == .complete)
    #expect(requestCount.count >= 2)
    #expect(
      restarted.destinationURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
    )
  }

  @Test("an interrupted transfer without resume data shows the transfer's own reason")
  func interruptedTransferShowsItsReason() async throws {
    let pkg = makePKGFixture(repetitions: 512)
    let server = try FixtureHTTPServer { _ in
      var response = FixtureHTTPResponse(body: pkg)
      response.chunkSize = 8 * 1024
      response.interruptAfterBytes = pkg.count / 3
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
        sourceURL: server.baseURL.appendingPathComponent("interrupt"),
        title: "Interrupted",
        consoleType: "PSV",
        expectedByteCount: Int64(pkg.count)
      )
    )

    let interrupted = try await waitForTerminal(coordinator, id: job.id)
    let message = try #require(interrupted.errorMessage)
    #expect(interrupted.state == .failed)
    #expect(
      message.hasSuffix("No valid resume data was provided; restart to try from the beginning.")
    )
    #expect(!message.contains("TransferFailure"))
    #expect(!message.hasPrefix(" "))
  }
}

extension CompatibilityPackTests {
  @Test("downloads pack then patch and overlays into the title-ID rePatch folder")
  func compositePackAndPatch() async throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let pack = try createZipArchive(
      at: workspace.appendingPathComponent("pack.zip"),
      files: ["content/config.txt": "base config", "content/base.dat": "base"]
    )
    let patch = try createZipArchive(
      at: workspace.appendingPathComponent("patch.zip"),
      files: ["content/config.txt": "patched config", "content/update.dat": "patch"]
    )
    let log = CompatibilityRequestLog()
    let server = try FixtureHTTPServer { request in
      log.append(request.path)
      return FixtureHTTPResponse(body: request.path == "/patch" ? patch : pack)
    }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    let preexistingOutput = library.appendingPathComponent(
      "PSV/rePatch/PCSA00001",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: preexistingOutput,
      withIntermediateDirectories: true
    )
    try Data("stale content must be replaced by the new CPack".utf8).write(
      to: preexistingOutput.appendingPathComponent("stale.dat")
    )
    let helper = workspace.appendingPathComponent("pkg2zip-do-not-run")
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 2) },
      persistenceURL: workspace.appendingPathComponent("downloads.plist"),
      extractor: Pkg2ZipExtractor(executableURL: helper),
      urlSessionConfiguration: .ephemeral
    )

    let queued = try await coordinator.enqueueCompatibilityPack(
      CompatibilityPackRequest(
        titleID: "PCSA00001",
        title: "Test Compatibility Pack",
        packURL: server.baseURL.appendingPathComponent("pack"),
        patchURL: server.baseURL.appendingPathComponent("patch")
      )
    )
    let result = try await waitForTerminal(coordinator, id: queued.id)
    #expect(result.state == .complete)
    #expect(log.paths == ["/pack", "/patch"])
    let output = library.appendingPathComponent("PSV/rePatch/PCSA00001", isDirectory: true)
    #expect(result.extractedDirectoryURL == output)
    #expect(await coordinator.revealURL(for: queued.id) == output)
    #expect(
      String(
        bytes: try Data(contentsOf: output.appendingPathComponent("content/config.txt")),
        encoding: .utf8
      ) == "patched config"
    )
    #expect(
      String(
        bytes: try Data(contentsOf: output.appendingPathComponent("content/base.dat")),
        encoding: .utf8
      ) == "base"
    )
    #expect(
      String(
        bytes: try Data(contentsOf: output.appendingPathComponent("content/update.dat")),
        encoding: .utf8
      ) == "patch"
    )
    #expect(
      !FileManager.default.fileExists(atPath: output.appendingPathComponent("stale.dat").path)
    )
    #expect(result.destinationURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    #expect(
      result.compatibilityPatchDestinationURL.map {
        FileManager.default.fileExists(atPath: $0.path)
      } == true
    )
    #expect(result.hasVerifiedPackage)
    #expect(!FileManager.default.fileExists(atPath: helper.path))
  }

  @Test(
    "disabled compatibility extraction keeps both verified PPK archives and skips output changes"
  )
  func compatibilityExtractionPreferenceOffKeepsArchives() async throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let pack = storedZip([StoredZipEntry(name: "base.dat", data: Data("new base".utf8))])
    let patch = storedZip([StoredZipEntry(name: "patch.dat", data: Data("new patch".utf8))])
    let server = try FixtureHTTPServer { request in
      FixtureHTTPResponse(body: request.path == "/patch" ? patch : pack)
    }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    let existingOutput = library.appendingPathComponent("PSV/rePatch/PCSB01101", isDirectory: true)
    try FileManager.default.createDirectory(at: existingOutput, withIntermediateDirectories: true)
    try Data("leave existing output untouched".utf8).write(
      to: existingOutput.appendingPathComponent("existing.dat")
    )
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 1) },
      persistenceURL: workspace.appendingPathComponent("downloads.plist"),
      urlSessionConfiguration: .ephemeral
    )

    let queued = try await coordinator.enqueueCompatibilityPack(
      CompatibilityPackRequest(
        titleID: "PCSB01101",
        title: "Example Base Pack",
        packURL: server.baseURL.appendingPathComponent("pack"),
        patchURL: server.baseURL.appendingPathComponent("patch"),
        extractAfterDownload: false
      )
    )
    let result = try await waitForTerminal(coordinator, id: queued.id)

    #expect(result.state == .complete)
    #expect(!result.request.extractAfterDownload)
    #expect(result.packageVerified)
    #expect(result.compatibilityPatchVerified)
    #expect(result.extractedDirectoryURL == nil)
    let packURL = try #require(result.destinationURL)
    let patchURL = try #require(result.compatibilityPatchDestinationURL)
    #expect(try Data(contentsOf: packURL) == pack)
    #expect(try Data(contentsOf: patchURL) == patch)
    #expect(
      try Data(contentsOf: existingOutput.appendingPathComponent("existing.dat"))
        == Data("leave existing output untouched".utf8)
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: existingOutput.appendingPathComponent("base.dat").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: existingOutput.appendingPathComponent("patch.dat").path
      )
    )
  }

  @Test("quitting while a pack verifies does not start its patch download")
  func shutdownDuringPackVerificationDefersThePatch() async throws {
    // Arrange: hold the pack between validation and install.
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let pack = try createZipArchive(
      at: workspace.appendingPathComponent("pack.zip"),
      files: ["file.txt": "base"]
    )
    let patchRequests = LockedPatchRequestFlag()
    let server = try FixtureHTTPServer { request in
      if request.path == "/patch" { patchRequests.markRequested() }
      return FixtureHTTPResponse(body: pack)
    }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    let persistenceURL = workspace.appendingPathComponent("downloads.plist")
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 1) },
      persistenceURL: persistenceURL,
      urlSessionConfiguration: .ephemeral
    )
    let gate = ValidationGate()
    await coordinator.setAfterValidation { _ in await gate.hold() }
    let queued = try await coordinator.enqueueCompatibilityPack(
      CompatibilityPackRequest(
        titleID: "PCSA00003",
        title: "Quit During Verify",
        packURL: server.baseURL.appendingPathComponent("pack"),
        patchURL: server.baseURL.appendingPathComponent("patch")
      )
    )
    await gate.waitUntilHeld()

    // Act: Quit starts draining while the pack is still being verified.
    let drain = Task { try await coordinator.pauseAll() }
    while await !coordinator.isDrainingForShutdown { await Task.yield() }
    await coordinator.setAfterValidation(nil)
    await gate.release()
    try await drain.value

    // Assert: the verified pack is kept and the patch waits for the next launch.
    let drained = try #require(await coordinator.snapshots().first { $0.id == queued.id })
    #expect(drained.state == .queued)
    #expect(drained.packageVerified)
    #expect(drained.compatibilityPatchVerified == false)
    #expect(!patchRequests.wasRequested)
  }

  @Test("a patch download failure keeps the completed pack archive and does not start extraction")
  func patchFailurePreservesPack() async throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let pack = try createZipArchive(
      at: workspace.appendingPathComponent("pack.zip"),
      files: ["file.txt": "base"]
    )
    let server = try FixtureHTTPServer { request in
      request.path == "/patch"
        ? FixtureHTTPResponse(status: 503, body: Data("offline".utf8))
        : FixtureHTTPResponse(body: pack)
    }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    let persistenceURL = workspace.appendingPathComponent("downloads.plist")
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 1) },
      persistenceURL: persistenceURL,
      urlSessionConfiguration: .ephemeral
    )
    let queued = try await coordinator.enqueueCompatibilityPack(
      CompatibilityPackRequest(
        titleID: "PCSA00002",
        title: "Patch Failure",
        packURL: server.baseURL.appendingPathComponent("pack"),
        patchURL: server.baseURL.appendingPathComponent("patch")
      )
    )
    let result = try await waitForTerminal(coordinator, id: queued.id)
    #expect(result.state == .failed)
    #expect(result.errorMessage?.contains("HTTP status 503") == true)
    #expect(result.destinationURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    #expect(result.packageVerified)
    #expect(result.compatibilityPatchVerified == false)
    #expect(result.hasVerifiedPackage == false)
    #expect(result.extractedDirectoryURL == nil)
    #expect(
      !FileManager.default.fileExists(
        atPath: library.appendingPathComponent("PSV/rePatch/PCSA00002").path
      )
    )
  }

  @Test("failed extraction keeps the downloaded archive and writes no traversal output")
  func traversalFailureKeepsDownloadedArchive() async throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let maliciousArchive = storedZip([
      StoredZipEntry(name: "../escaped.txt", data: Data("escaped".utf8))
    ])
    let server = try FixtureHTTPServer { _ in FixtureHTTPResponse(body: maliciousArchive) }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 1) },
      persistenceURL: workspace.appendingPathComponent("downloads.plist"),
      urlSessionConfiguration: .ephemeral
    )
    let queued = try await coordinator.enqueueCompatibilityPack(
      CompatibilityPackRequest(
        titleID: "PCSA00003",
        title: "Unsafe Archive",
        packURL: server.baseURL.appendingPathComponent("unsafe")
      )
    )
    let result = try await waitForTerminal(coordinator, id: queued.id)
    #expect(result.state == .failed)
    #expect(result.errorMessage?.contains("unsafe entry") == true)
    #expect(result.destinationURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    #expect(result.hasVerifiedPackage)
    #expect(
      !FileManager.default.fileExists(
        atPath: library.appendingPathComponent("PSV/escaped.txt").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: library.appendingPathComponent("PSV/rePatch/PCSA00003/escaped.txt").path
      )
    )
  }

  @Test("legacy direct .ppk requests still save the archive without invoking pkg2zip")
  func rawPPKDownloadRemainsSupported() async throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let archive = try createZipArchive(
      at: workspace.appendingPathComponent("raw.zip"),
      files: ["data.bin": "raw data"]
    )
    let server = try FixtureHTTPServer { _ in FixtureHTTPResponse(body: archive) }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    let helper = workspace.appendingPathComponent("pkg2zip-should-not-run")
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 1) },
      persistenceURL: workspace.appendingPathComponent("downloads.plist"),
      extractor: Pkg2ZipExtractor(executableURL: helper),
      urlSessionConfiguration: .ephemeral
    )
    let queued = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("raw"),
        title: "Old Direct PPK",
        consoleType: "PSV",
        titleID: "PCSA00004",
        fileExtension: "ppk"
      )
    )
    let result = try await waitForTerminal(coordinator, id: queued.id)
    #expect(result.state == .complete)
    #expect(result.hasVerifiedPackage)
    #expect(result.extractedDirectoryURL == nil)
    #expect(
      !FileManager.default.fileExists(atPath: library.appendingPathComponent("PSV/rePatch").path)
    )
    #expect(!FileManager.default.fileExists(atPath: helper.path))
  }

  @Test("standalone CPatch mode verifies the archive without extracting when the setting is off")
  func patchOnlyModePreservesArchiveWhenExtractionIsDisabled() async throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let archive = storedZip([StoredZipEntry(name: "patch.dat", data: Data("patch bytes".utf8))])
    let server = try FixtureHTTPServer { _ in FixtureHTTPResponse(body: archive) }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    let persistenceURL = workspace.appendingPathComponent("downloads.plist")
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 1) },
      persistenceURL: persistenceURL,
      urlSessionConfiguration: .ephemeral
    )

    let queued = try await coordinator.enqueue(
      DownloadJobRequest(
        sourceURL: server.baseURL.appendingPathComponent("patch"),
        title: "Shovel Knight",
        consoleType: "PSV",
        titleID: "PCSE00640",
        fileExtension: "ppk",
        extractAfterDownload: false,
        compatibilityPatchMode: .overlayExistingOutput
      )
    )
    let result = try await waitForTerminal(coordinator, id: queued.id)

    #expect(result.state == .complete)
    #expect(result.packageVerified)
    #expect(!result.request.extractAfterDownload)
    #expect(result.extractedDirectoryURL == nil)
    let package = try #require(result.destinationURL)
    #expect(try Data(contentsOf: package) == archive)
    #expect(
      !FileManager.default.fileExists(
        atPath: library.appendingPathComponent("PSV/rePatch/PCSE00640").path
      )
    )

    let restoredCoordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 1) },
      persistenceURL: persistenceURL,
      urlSessionConfiguration: .ephemeral
    )
    let restored = try #require(await restoredCoordinator.snapshots().first)
    #expect(restored.request.compatibilityPatchMode == .overlayExistingOutput)
    #expect(!restored.request.extractAfterDownload)
  }

  @Test("patch-only Shovel Knight and Minecraft PPKs extract safely and retain failures")
  func patchOnlyFeedEntriesUseTheirOwnTitleFolders() async throws {
    let workspace = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let shovelKnightArchive = storedZip([
      StoredZipEntry(name: "data/shovel-knight.txt", data: Data("fixture patch output".utf8))
    ])
    let maliciousMinecraftArchive = storedZip([
      StoredZipEntry(name: "../escaped.txt", data: Data("must not escape".utf8))
    ])
    let server = try FixtureHTTPServer { request in
      FixtureHTTPResponse(
        body: request.path.contains("PCSE00640") ? shovelKnightArchive : maliciousMinecraftArchive
      )
    }
    let library = workspace.appendingPathComponent("library", isDirectory: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    let shovelBase = library.appendingPathComponent("PSV/rePatch/PCSE00640", isDirectory: true)
    try FileManager.default.createDirectory(at: shovelBase, withIntermediateDirectories: true)
    try Data("existing Shovel Knight base".utf8).write(
      to: shovelBase.appendingPathComponent("base.dat")
    )
    let coordinator = try DownloadCoordinator(
      preferences: { DownloadPreferences(downloadDirectory: library, concurrentDownloads: 2) },
      persistenceURL: workspace.appendingPathComponent("downloads.plist"),
      urlSessionConfiguration: .ephemeral
    )
    let cases: [(String, String)] = [
      ("PCSE00640", "Shovel Knight"), ("PCSE00491", "Minecraft: PlayStation Vita Edition"),
    ]
    var ids: [UUID] = []
    for (titleID, title) in cases {
      let queued = try await coordinator.enqueue(
        DownloadJobRequest(
          sourceURL: server.baseURL.appendingPathComponent("patch/\(titleID)"),
          title: title,
          consoleType: "PSV",
          titleID: titleID,
          fileExtension: "ppk",
          extractAfterDownload: true,
          extractionOptions: PackageExtractionOptions(keepPackage: false),
          compatibilityPatchMode: .overlayExistingOutput
        )
      )
      ids.append(queued.id)
    }

    let results = try await withThrowingTaskGroup(
      of: DownloadSnapshot.self,
      returning: [DownloadSnapshot].self
    ) { group in
      for id in ids { group.addTask { try await waitForTerminal(coordinator, id: id) } }
      var values: [DownloadSnapshot] = []
      for try await result in group { values.append(result) }
      return values
    }
    let resultByID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
    let shovelKnight = try #require(resultByID[ids[0]])
    #expect(shovelKnight.request.title == "Shovel Knight")
    #expect(shovelKnight.state == .complete)
    let shovelOutput = library.appendingPathComponent("PSV/rePatch/PCSE00640", isDirectory: true)
    #expect(shovelKnight.extractedDirectoryURL == shovelOutput)
    #expect(
      String(
        bytes: try Data(contentsOf: shovelOutput.appendingPathComponent("data/shovel-knight.txt")),
        encoding: .utf8
      ) == "fixture patch output"
    )
    #expect(
      try Data(contentsOf: shovelOutput.appendingPathComponent("base.dat"))
        == Data("existing Shovel Knight base".utf8)
    )
    #expect(
      shovelKnight.destinationURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true
    )

    let minecraft = try #require(resultByID[ids[1]])
    #expect(minecraft.request.title == "Minecraft: PlayStation Vita Edition")
    #expect(minecraft.state == .failed)
    #expect(minecraft.errorMessage?.contains("unsafe entry") == true)
    let preservedArchive = try #require(minecraft.destinationURL)
    #expect(try Data(contentsOf: preservedArchive) == maliciousMinecraftArchive)
    #expect(minecraft.hasVerifiedPackage)
    #expect(
      !FileManager.default.fileExists(
        atPath: library.appendingPathComponent("PSV/escaped.txt").path
      )
    )
  }
}
