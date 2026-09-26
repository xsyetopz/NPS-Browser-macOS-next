import Foundation
import Testing
@testable import NPSDownloads

private final class LegacyRequestCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func increment() {
    lock.lock()
    defer { lock.unlock() }
    value += 1
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  var isEmpty: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value == 0
  }

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    value = 0
  }
}

private final class ResumeDataCapture: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data?, Never>?
  private var cancellationRequested = false

  func capture(from url: URL, using session: URLSession) async -> Data? {
    await withCheckedContinuation { continuation in
      lock.lock()
      self.continuation = continuation
      lock.unlock()
      session.downloadTask(with: url).resume()
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesWritten > 0 else { return }
    lock.lock()
    let shouldCancel = !cancellationRequested
    cancellationRequested = true
    lock.unlock()
    guard shouldCancel else { return }
    downloadTask.cancel { [weak self] data in self?.finish(data) }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) { finish(nil) }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard error != nil else { return }
    lock.lock()
    let wasCanceledForResume = cancellationRequested
    lock.unlock()
    if !wasCanceledForResume { finish(nil) }
  }

  private func finish(_ data: Data?) {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    continuation?.resume(returning: data)
  }
}

private enum LegacyDownloadTestError: Error { case timedOut(UUID) }

private struct LegacyDownloadListFixture: Encodable { let items: [LegacyDownloadItemFixture] }

/// Encodes the archived `DLItem.CodingKeys` in binary-plist form.
private struct LegacyDownloadItemFixture: Encodable {
  let titleId: String?
  let name: String?
  let downloadUrl: URL?
  let progress: Double
  let zrif: String?
  let status: String?
  let timeRemaining: Double
  let resumeData: Data?
  let destinationURL: URL?
  let isStoppable: Bool
  let isViewable: Bool
  let isRemovable: Bool
  let isResumable: Bool
  let consoleType: String?
  let fileType: String?
}

@Test(.sourceEnglish)
func importsArchivedQueueBeforeAnyTransferAndPreservesCompletedDestination() async throws {
  let root = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }

  let requests = LegacyRequestCounter()
  let server = try FixtureHTTPServer { _ in
    requests.increment()
    return FixtureHTTPResponse(body: Data("should not start".utf8))
  }
  let resumeRequests = LegacyRequestCounter()
  let packageBytes = Data(
    [0x50, 0x4b, 0x03, 0x04] + Array(repeating: 0x5a, count: 2 * 1024 * 1024 - 4)
  )
  let resumeServer = try FixtureHTTPServer { request in
    resumeRequests.increment()
    var response: FixtureHTTPResponse
    if let range = request.headers["range"],
      let offsetText = range.split(separator: "=").last?.split(separator: "-").first,
      let offset = Int(offsetText), offset >= 0, offset < packageBytes.count
    {
      response = FixtureHTTPResponse(status: 206, body: Data(packageBytes.dropFirst(offset)))
      response.headers["Content-Range"] =
        "bytes \(offset)-\(packageBytes.count - 1)/\(packageBytes.count)"
    } else {
      response = FixtureHTTPResponse(body: packageBytes)
      response.chunkSize = 4 * 1024
      response.chunkDelayMicroseconds = 3_000
    }
    response.headers["Accept-Ranges"] = "bytes"
    response.headers["ETag"] = "\"legacy-resume-fixture\""
    return response
  }
  let resumeDelegate = ResumeDataCapture()
  let resumeTestSession = URLSession(
    configuration: .ephemeral,
    delegate: resumeDelegate,
    delegateQueue: nil
  )
  let archivedResumeData = await resumeDelegate.capture(
    from: resumeServer.baseURL.appendingPathComponent("resumable.ppk"),
    using: resumeTestSession
  )
  resumeTestSession.invalidateAndCancel()
  let resumeData = try #require(archivedResumeData)
  #expect(!resumeData.isEmpty)
  resumeRequests.reset()
  let completedDestination = root.appendingPathComponent("Old Library/PS3/Finished.pkg")
  let resumableDestination = root.appendingPathComponent("Old Library/PSV/Paused.ppk")
  try FileManager.default.createDirectory(
    at: completedDestination.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try FileManager.default.createDirectory(
    at: resumableDestination.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  let completedBytes = Data("legacy completed file".utf8)
  try completedBytes.write(to: completedDestination)
  try Data("legacy partial file".utf8).write(to: resumableDestination)

  let legacy = try encodeLegacyList([
    legacyItem(
      titleID: "NPUB12345",
      name: "Finished game",
      sourceURL: server.baseURL.appendingPathComponent("finished.pkg"),
      status: "Download Complete",
      destinationURL: completedDestination,
      consoleType: "PS3",
      fileType: "Game",
      isViewable: true
    ),
    legacyItem(
      titleID: "PCSB01101",
      name: "Paused pack",
      sourceURL: resumeServer.baseURL.appendingPathComponent("resumable.ppk"),
      status: "Stopped",
      resumeData: resumeData,
      destinationURL: resumableDestination,
      consoleType: "PSV",
      fileType: "CPack",
      progress: 37,
      zrif: "legacy-license"
    ),
    legacyItem(
      titleID: "NPUB54321",
      name: "Interrupted DLC",
      sourceURL: server.baseURL.appendingPathComponent("interrupted.pkg"),
      status: "Stopped",
      consoleType: "PS3",
      fileType: "DLC",
      progress: 42
    ),
  ])
  #expect(legacy.starts(with: Data("bplist00".utf8)))

  let currentLibrary = root.appendingPathComponent("New Library", isDirectory: true)
  let backupDirectory = root.appendingPathComponent("LegacyDownloadBackups", isDirectory: true)
  let persistenceURL = root.appendingPathComponent("downloads.plist")
  let defaultsSuite = "NPSLegacyMigration-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
  defaults.set(legacy, forKey: "downloads")
  defer { defaults.removePersistentDomain(forName: defaultsSuite) }
  let coordinator = try makeCoordinator(
    destination: currentLibrary,
    persistence: persistenceURL,
    legacyData: try #require(defaults.data(forKey: "downloads")),
    backupDirectory: backupDirectory
  )
  #expect(defaults.data(forKey: "downloads") == legacy)
  let snapshots = await coordinator.snapshots()
  let completed = try #require(snapshots.first { $0.request.title == "Finished game" })
  let paused = try #require(snapshots.first { $0.request.title == "Paused pack" })
  let interrupted = try #require(snapshots.first { $0.request.title == "Interrupted DLC" })

  #expect(snapshots.count == 3)
  #expect(completed.state == .complete)
  #expect(completed.destinationURL == completedDestination)
  #expect(completed.completedURL == completedDestination)
  #expect(!completed.packageVerified)
  #expect(try Data(contentsOf: completedDestination) == completedBytes)

  #expect(paused.state == .paused)
  #expect(paused.canResume)
  #expect(paused.destinationURL == resumableDestination)
  #expect(paused.request.sourceURL == resumeServer.baseURL.appendingPathComponent("resumable.ppk"))
  #expect(paused.request.titleID == "PCSB01101")
  #expect(paused.request.consoleType == "PSV")
  #expect(paused.request.fileExtension == "ppk")
  #expect(paused.request.zrif == "legacy-license")
  #expect(paused.progress == 0.37)
  #expect(paused.errorMessage?.contains("resume") == true)

  #expect(interrupted.state == .failed)
  #expect(interrupted.canRestart)
  #expect(interrupted.request.fileExtension == "pkg")
  #expect(
    interrupted.destinationDirectory
      == currentLibrary.appendingPathComponent("PS3", isDirectory: true)
  )
  #expect(interrupted.errorMessage?.contains("without resume data") == true)
  #expect(snapshots.allSatisfy { $0.state != .queued && $0.state != .downloading })
  #expect(requests.isEmpty)
  #expect(resumeRequests.isEmpty)

  try await coordinator.resume(paused.id)
  let resumed = try await waitForLegacyTerminal(coordinator, id: paused.id)
  #expect(resumed.state == .complete)
  let resumedDestination = try #require(resumed.destinationURL)
  #expect(resumedDestination != resumableDestination)
  #expect(try Data(contentsOf: resumableDestination) == Data("legacy partial file".utf8))
  #expect(try Data(contentsOf: resumedDestination) == packageBytes)
  #expect(!resumeRequests.isEmpty)

  let backupFiles = try FileManager.default.contentsOfDirectory(
    at: backupDirectory,
    includingPropertiesForKeys: nil
  )
  #expect(backupFiles.count == 1)
  #expect(try Data(contentsOf: backupFiles[0]) == legacy)
  #expect(FileManager.default.fileExists(atPath: persistenceURL.path))
}

@Test(.sourceEnglish)
func malformedLegacyQueueLeavesRawDataRecoverableAndCreatesNoQueue() async throws {
  let root = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }

  let persistenceURL = root.appendingPathComponent("downloads.plist")
  let backupDirectory = root.appendingPathComponent("LegacyDownloadBackups", isDirectory: true)
  let malformed = Data("not a binary plist".utf8)
  let defaultsSuite = "NPSLegacyMalformed-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
  defaults.set(malformed, forKey: "downloads")
  defer { defaults.removePersistentDomain(forName: defaultsSuite) }
  do {
    _ = try makeCoordinator(
      destination: root.appendingPathComponent("Library", isDirectory: true),
      persistence: persistenceURL,
      legacyData: try #require(defaults.data(forKey: "downloads")),
      backupDirectory: backupDirectory
    )
    Issue.record("Malformed legacy data should not create a queue.")
  } catch let error as LegacyDownloadMigrationError {
    #expect(error.localizedDescription.contains("original data was kept"))
    #expect(error.localizedDescription.contains("no jobs were imported"))
  }

  #expect(!FileManager.default.fileExists(atPath: persistenceURL.path))
  #expect(defaults.data(forKey: "downloads") == malformed)
  let backupFiles = try FileManager.default.contentsOfDirectory(
    at: backupDirectory,
    includingPropertiesForKeys: nil
  )
  #expect(backupFiles.count == 1)
  #expect(try Data(contentsOf: backupFiles[0]) == malformed)

  let valid = try encodeLegacyList([
    legacyItem(
      titleID: "NPUB99999",
      name: "Recoverable game",
      sourceURL: URL(string: "https://downloads.example/recoverable.pkg")!,
      status: "Stopped",
      consoleType: "PS3",
      fileType: "Game"
    )
  ])
  let recovered = try makeCoordinator(
    destination: root.appendingPathComponent("Library", isDirectory: true),
    persistence: persistenceURL,
    legacyData: valid,
    backupDirectory: backupDirectory
  )
  let recoveredJobs = await recovered.snapshots()
  #expect(recoveredJobs.count == 1)
  #expect(recoveredJobs[0].state == .failed)
  #expect(recoveredJobs[0].request.title == "Recoverable game")
}

@Test(.sourceEnglish)
func archivedPSVExtractionLocationBecomesRevealableWhenVolumeReturns() async throws {
  let root = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }

  let library = root.appendingPathComponent("Old Library", isDirectory: true)
  let consoleDirectory = library.appendingPathComponent("PSV", isDirectory: true)
  try FileManager.default.createDirectory(at: consoleDirectory, withIntermediateDirectories: true)

  let expectedOutputs: [(String, String, URL)] = [
    (
      "PCSA00007", "Game",
      consoleDirectory.appendingPathComponent("app/PCSA00007", isDirectory: true)
    ),
    (
      "PCSB01101", "DLC",
      consoleDirectory.appendingPathComponent("addcont/PCSB01101", isDirectory: true)
    ),
    (
      "PCSE00003", "Update",
      consoleDirectory.appendingPathComponent("patch/PCSE00003", isDirectory: true)
    ),
  ]
  for (_, _, output) in expectedOutputs {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try Data("extracted content".utf8).write(to: output.appendingPathComponent("content.bin"))
  }

  let missingOutputTitleID = "PCSA00008"
  let missingOutput = consoleDirectory.appendingPathComponent(
    "app/\(missingOutputTitleID)",
    isDirectory: true
  )
  let unknownPackage = consoleDirectory.appendingPathComponent("Unknown extraction.pkg")
  try Data("archived package, not extracted output".utf8).write(to: unknownPackage)

  var items = expectedOutputs.map { titleID, fileType, _ in
    legacyItem(
      titleID: titleID,
      name: "Extracted \(fileType)",
      sourceURL: URL(string: "https://downloads.example/\(titleID).pkg")!,
      status: "Extraction Complete",
      destinationURL: consoleDirectory.appendingPathComponent("\(titleID).pkg"),
      consoleType: "PSV",
      fileType: fileType
    )
  }
  items.append(
    legacyItem(
      titleID: missingOutputTitleID,
      name: "Missing output",
      sourceURL: URL(string: "https://downloads.example/missing.pkg")!,
      status: "Extraction Complete",
      destinationURL: consoleDirectory.appendingPathComponent("\(missingOutputTitleID).pkg"),
      consoleType: "PSV",
      fileType: "Game"
    )
  )
  items.append(
    legacyItem(
      titleID: "PCSA00009",
      name: "Unknown output",
      sourceURL: URL(string: "https://downloads.example/unknown.pkg")!,
      status: "Extraction Complete",
      destinationURL: unknownPackage,
      consoleType: "PSV",
      fileType: "Other"
    )
  )

  let coordinator = try makeCoordinator(
    destination: root.appendingPathComponent("New Library", isDirectory: true),
    persistence: root.appendingPathComponent("downloads.plist"),
    legacyData: try encodeLegacyList(items),
    backupDirectory: root.appendingPathComponent("LegacyDownloadBackups", isDirectory: true)
  )
  let snapshots = await coordinator.snapshots()

  for (titleID, _, output) in expectedOutputs {
    let snapshot = try #require(snapshots.first { $0.request.titleID == titleID })
    #expect(snapshot.state == .complete)
    #expect(snapshot.request.fileExtension == "pkg")
    #expect(snapshot.extractedDirectoryURL == output)
    #expect(snapshot.completedURL == output)
    #expect(!snapshot.packageVerified)
    #expect(snapshot.legacyOutputLocationUnknown == false)
  }
  let missing = try #require(snapshots.first { $0.request.titleID == missingOutputTitleID })
  #expect(missing.state == .complete)
  #expect(missing.extractedDirectoryURL == missingOutput)
  #expect(missing.completedURL == nil)
  #expect(missing.legacyOutputLocationUnknown == false)
  #expect(missing.errorMessage?.contains("legacy-output-location-missing") == true)

  try FileManager.default.createDirectory(at: missingOutput, withIntermediateDirectories: true)
  try Data("mounted extracted content".utf8).write(
    to: missingOutput.appendingPathComponent("content.bin")
  )
  let visibleAfterRemount = try #require(
    await coordinator.snapshots().first { $0.request.titleID == missingOutputTitleID }
  )
  #expect(visibleAfterRemount.extractedDirectoryURL == missingOutput)
  #expect(visibleAfterRemount.completedURL == missingOutput)
  #expect(visibleAfterRemount.errorMessage == nil)

  let unknown = try #require(snapshots.first { $0.request.titleID == "PCSA00009" })
  #expect(unknown.state == .complete)
  #expect(unknown.destinationURL == unknownPackage)
  #expect(FileManager.default.fileExists(atPath: unknownPackage.path))
  #expect(unknown.extractedDirectoryURL == nil)
  #expect(unknown.completedURL == nil)
  #expect(unknown.legacyOutputLocationUnknown == true)
  #expect(unknown.errorMessage?.contains("legacy-output-location-unknown") == true)
}

@Test(.sourceEnglish)
func removedImportedJobDoesNotReturnOnUnchangedLegacyArchive() async throws {
  let root = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let archivedItem = legacyItem(
    titleID: "NPUB99101",
    name: "Removed legacy job",
    sourceURL: URL(string: "https://downloads.example/removed.pkg")!,
    status: "Stopped",
    consoleType: "PS3",
    fileType: "Game"
  )
  let archive = try encodeLegacyList([archivedItem])
  let persistenceURL = root.appendingPathComponent("downloads.plist")
  let backupDirectory = root.appendingPathComponent("LegacyDownloadBackups", isDirectory: true)
  let destination = root.appendingPathComponent("Library", isDirectory: true)

  let firstLaunch = try makeCoordinator(
    destination: destination,
    persistence: persistenceURL,
    legacyData: archive,
    backupDirectory: backupDirectory
  )
  let imported = try #require(await firstLaunch.snapshots().first)
  try await firstLaunch.remove(imported.id)
  #expect(await firstLaunch.snapshots().isEmpty)

  let relaunch = try makeCoordinator(
    destination: destination,
    persistence: persistenceURL,
    legacyData: archive,
    backupDirectory: backupDirectory
  )
  #expect(await relaunch.snapshots().isEmpty)
}

@Test(.sourceEnglish)
func changedLegacyArchiveIsBackedUpAndImportedThenRecorded() async throws {
  let root = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let firstItem = legacyItem(
    titleID: "NPUB99102",
    name: "First archived job",
    sourceURL: URL(string: "https://downloads.example/first.pkg")!,
    status: "Stopped",
    consoleType: "PS3",
    fileType: "Game"
  )
  let secondItem = legacyItem(
    titleID: "NPUB99103",
    name: "Later archived job",
    sourceURL: URL(string: "https://downloads.example/later.pkg")!,
    status: "Stopped",
    consoleType: "PS3",
    fileType: "Game"
  )
  let firstArchive = try encodeLegacyList([firstItem])
  let changedArchive = try encodeLegacyList([firstItem, secondItem])
  let persistenceURL = root.appendingPathComponent("downloads.plist")
  let backupDirectory = root.appendingPathComponent("LegacyDownloadBackups", isDirectory: true)
  let destination = root.appendingPathComponent("Library", isDirectory: true)

  _ = try makeCoordinator(
    destination: destination,
    persistence: persistenceURL,
    legacyData: firstArchive,
    backupDirectory: backupDirectory
  )
  let changedLaunch = try makeCoordinator(
    destination: destination,
    persistence: persistenceURL,
    legacyData: changedArchive,
    backupDirectory: backupDirectory
  )
  let changedSnapshots = await changedLaunch.snapshots()
  #expect(
    Set(changedSnapshots.map(\.request.title)) == ["First archived job", "Later archived job"]
  )

  let first = try #require(changedSnapshots.first { $0.request.title == "First archived job" })
  try await changedLaunch.remove(first.id)

  let afterChangeWasRecorded = try makeCoordinator(
    destination: destination,
    persistence: persistenceURL,
    legacyData: changedArchive,
    backupDirectory: backupDirectory
  )
  #expect(await afterChangeWasRecorded.snapshots().map(\.request.title) == ["Later archived job"])

  let backups = try FileManager.default.contentsOfDirectory(
    at: backupDirectory,
    includingPropertiesForKeys: nil
  )
  #expect(backups.count == 2)
  #expect(Set(try backups.map { try Data(contentsOf: $0) }) == [firstArchive, changedArchive])
}

@Test(.sourceEnglish)
func legacyImportLedgerIsNotWrittenUntilQueueSaveSucceeds() async throws {
  let root = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let archive = try encodeLegacyList([
    legacyItem(
      titleID: "NPUB99104",
      name: "Ledger ordering",
      sourceURL: URL(string: "https://downloads.example/ledger.pkg")!,
      status: "Stopped",
      consoleType: "PS3",
      fileType: "Game"
    )
  ])
  let blockedParent = root.appendingPathComponent("queue-parent")
  try Data("not a directory".utf8).write(to: blockedParent)
  let persistenceURL = blockedParent.appendingPathComponent("downloads.plist")
  let backupDirectory = root.appendingPathComponent("LegacyDownloadBackups", isDirectory: true)
  let ledgerURL = URL(fileURLWithPath: persistenceURL.path + ".legacy-import")

  do {
    _ = try makeCoordinator(
      destination: root.appendingPathComponent("Library", isDirectory: true),
      persistence: persistenceURL,
      legacyData: archive,
      backupDirectory: backupDirectory
    )
    Issue.record("A native queue write failure should stop initialization.")
  } catch {
    #expect(!FileManager.default.fileExists(atPath: persistenceURL.path))
    #expect(!FileManager.default.fileExists(atPath: ledgerURL.path))
    let backups = try FileManager.default.contentsOfDirectory(
      at: backupDirectory,
      includingPropertiesForKeys: nil
    )
    #expect(backups.count == 1)
    #expect(try Data(contentsOf: backups[0]) == archive)
  }

  try FileManager.default.removeItem(at: blockedParent)
  try FileManager.default.createDirectory(at: blockedParent, withIntermediateDirectories: true)
  let retry = try makeCoordinator(
    destination: root.appendingPathComponent("Library", isDirectory: true),
    persistence: persistenceURL,
    legacyData: archive,
    backupDirectory: backupDirectory
  )
  #expect(await retry.snapshots().count == 1)
  #expect(FileManager.default.fileExists(atPath: ledgerURL.path))
}

@Test(.sourceEnglish)
func repeatedLegacyImportKeepsStableIDsAndDoesNotDuplicateJobs() async throws {
  let root = try makeTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: root) }

  let duplicateRequest = legacyItem(
    titleID: "PCSA00007",
    name: "Paused Vita game",
    sourceURL: URL(string: "https://downloads.example/paused.pkg")!,
    status: "Stopped",
    consoleType: "PSV",
    fileType: "Game"
  )
  let legacy = try encodeLegacyList([duplicateRequest, duplicateRequest])
  let persistenceURL = root.appendingPathComponent("downloads.plist")
  let backupDirectory = root.appendingPathComponent("LegacyDownloadBackups", isDirectory: true)
  let library = root.appendingPathComponent("Library", isDirectory: true)

  let first = try makeCoordinator(
    destination: library,
    persistence: persistenceURL,
    legacyData: legacy,
    backupDirectory: backupDirectory
  )
  let firstSnapshots = await first.snapshots()
  let firstIDs = Set(firstSnapshots.map(\.id))
  let firstDestinations = Set(firstSnapshots.compactMap { $0.destinationURL?.path })

  let second = try makeCoordinator(
    destination: library,
    persistence: persistenceURL,
    legacyData: legacy,
    backupDirectory: backupDirectory
  )
  let secondSnapshots = await second.snapshots()

  #expect(firstSnapshots.count == 2)
  #expect(firstIDs.count == 2)
  #expect(firstDestinations.count == 2)
  #expect(Set(secondSnapshots.map(\.id)) == firstIDs)
  #expect(Set(secondSnapshots.compactMap { $0.destinationURL?.path }) == firstDestinations)
  #expect(secondSnapshots.allSatisfy { $0.state == .failed })
  let backupFiles = try FileManager.default.contentsOfDirectory(
    at: backupDirectory,
    includingPropertiesForKeys: nil
  )
  #expect(backupFiles.count == 1)
}

private func makeCoordinator(
  destination: URL,
  persistence: URL,
  legacyData: Data,
  backupDirectory: URL
) throws -> DownloadCoordinator {
  try DownloadCoordinator(
    preferences: { DownloadPreferences(downloadDirectory: destination, concurrentDownloads: 1) },
    persistenceURL: persistence,
    urlSessionConfiguration: .ephemeral,
    legacyDownloadListData: legacyData,
    legacyDownloadBackupDirectory: backupDirectory
  )
}

private func makeTemporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "NPSLegacyDownloads-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

private func encodeLegacyList(_ items: [LegacyDownloadItemFixture]) throws -> Data {
  let encoder = PropertyListEncoder()
  encoder.outputFormat = .binary
  return try encoder.encode(LegacyDownloadListFixture(items: items))
}

private func waitForLegacyTerminal(
  _ coordinator: DownloadCoordinator,
  id: UUID
) async throws -> DownloadSnapshot {
  for _ in 0..<600 {
    if let snapshot = await coordinator.snapshots().first(where: { $0.id == id }),
      snapshot.state == .complete || snapshot.state == .failed
    {
      return snapshot
    }
    try await Task.sleep(nanoseconds: 25_000_000)
  }
  throw LegacyDownloadTestError.timedOut(id)
}

private func legacyItem(
  titleID: String?,
  name: String?,
  sourceURL: URL?,
  status: String?,
  resumeData: Data? = nil,
  destinationURL: URL? = nil,
  consoleType: String?,
  fileType: String?,
  progress: Double = 0,
  zrif: String? = nil,
  isViewable: Bool = false
) -> LegacyDownloadItemFixture {
  LegacyDownloadItemFixture(
    titleId: titleID,
    name: name,
    downloadUrl: sourceURL,
    progress: progress,
    zrif: zrif,
    status: status,
    timeRemaining: 0,
    resumeData: resumeData,
    destinationURL: destinationURL,
    isStoppable: false,
    isViewable: isViewable,
    isRemovable: true,
    isResumable: resumeData != nil,
    consoleType: consoleType,
    fileType: fileType
  )
}
