import AppKit
import Foundation
import Testing
@testable import NPSBrowserApp

extension BrowserViewControllerTests {
  @Test
  func sameTitleJobCompletesItsOwnPendingRequestWhenItArrivesBeforeAnother() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSBrowser-volume-pending-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let outputDirectory = temporaryRoot.appendingPathComponent("MountedLibrary", isDirectory: true)
    let fixture = WorkspaceVolumeSnapshotFixture(extractedDirectory: outputDirectory)
    let enqueueGate = WorkspaceEnqueueGate()
    let notifications = NotificationCenter()
    let source = WorkspaceVolumeBrowserDataSource(fixture: fixture, enqueueGate: enqueueGate)
    let controller = BrowserViewController(
      dataSource: source,
      workspaceNotificationCenter: notifications
    )
    _ = controller.view

    let first = workspaceRefreshCatalogueEntry(
      id: "same-title-a",
      title: "Repeated Title",
      titleID: "PCSE76543",
      packageURL: URL(string: "https://example.test/first.pkg")!
    )
    let second = workspaceRefreshCatalogueEntry(
      id: "same-title-b",
      title: "Repeated Title",
      titleID: "PCSE76543",
      packageURL: URL(string: "https://example.test/second.pkg")!
    )
    controller.enqueue(first)
    await enqueueGate.waitUntilStarted(1)

    controller.showAllItems(nil)
    controller.enqueue(second)
    await enqueueGate.waitUntilStarted(2)
    try await waitForDownloadLoadCount(2, fixture: fixture)
    try await waitForDisplayedIDs(
      ["completed-volume-job", "queued-volume-job", "pending-\(first.id)", "pending-\(second.id)"],
      in: controller.downloadsController
    )

    let persistedJob = DownloadEntry(
      id: "durable-\(second.id)",
      title: first.title,
      detail: first.titleID,
      state: .queued,
      progress: 0,
      completedFile: nil,
      titleID: first.titleID,
      createdAt: Date().addingTimeInterval(60)
    )
    await fixture.replaceDownloads([persistedJob])
    let loadCountBeforeMount = await fixture.loadCount()
    notifications.post(name: NSWorkspace.didMountNotification, object: nil)
    try await waitForDownloadLoadCount(loadCountBeforeMount + 1, fixture: fixture)
    try await waitForDisplayedIDs(
      [persistedJob.id, "pending-\(first.id)", "pending-\(second.id)"],
      in: controller.downloadsController
    )

    await enqueueGate.release(2)
    try await waitForDownloadLoadCount(loadCountBeforeMount + 2, fixture: fixture)
    try await waitForDisplayedIDs(
      [persistedJob.id, "pending-\(first.id)"],
      in: controller.downloadsController
    )

    controller.showAllItems(nil)
    await enqueueGate.release(1)
    try await waitForDownloadLoadCount(loadCountBeforeMount + 3, fixture: fixture)
  }

  @Test
  func requestedJobInSnapshotReplacesItsPlaceholderBeforeEnqueueReturns() async throws {
    // Arrange
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSBrowser-pending-handoff-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let fixture = WorkspaceVolumeSnapshotFixture(extractedDirectory: temporaryRoot)
    await fixture.publishRequestedJobs()
    let enqueueGate = WorkspaceEnqueueGate()
    let notifications = NotificationCenter()
    let source = WorkspaceVolumeBrowserDataSource(fixture: fixture, enqueueGate: enqueueGate)
    let controller = BrowserViewController(
      dataSource: source,
      workspaceNotificationCenter: notifications
    )
    _ = controller.view
    let entry = workspaceRefreshCatalogueEntry()

    // Act: the job is published while the enqueue call is still suspended.
    controller.enqueue(entry)
    await enqueueGate.waitUntilStarted()
    let jobID = try #require(await fixture.requestedJobIDs().first)
    let loadsBeforeMount = await fixture.loadCount()
    notifications.post(name: NSWorkspace.didMountNotification, object: nil)
    try await waitForDownloadLoadCount(loadsBeforeMount + 1, fixture: fixture)

    // Assert: the job row replaces the placeholder; they never show together.
    let expected: Set<String> = ["completed-volume-job", "queued-volume-job", jobID.uuidString]
    try await waitForDisplayedIDs(expected, in: controller.downloadsController)
    await enqueueGate.release(1)
    try await waitForDownloadLoadCount(loadsBeforeMount + 2, fixture: fixture)
    try await waitForDisplayedIDs(expected, in: controller.downloadsController)

    controller.showAllItems(nil)
  }

  @Test
  func placeholderStaysVisibleUntilThePostEnqueueSnapshotArrives() async throws {
    // Arrange
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSBrowser-pending-gap-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let fixture = WorkspaceVolumeSnapshotFixture(extractedDirectory: temporaryRoot)
    let enqueueGate = WorkspaceEnqueueGate()
    let source = WorkspaceVolumeBrowserDataSource(fixture: fixture, enqueueGate: enqueueGate)
    let controller = BrowserViewController(
      dataSource: source,
      workspaceNotificationCenter: NotificationCenter()
    )
    _ = controller.view
    let entry = workspaceRefreshCatalogueEntry()
    controller.enqueue(entry)
    await enqueueGate.waitUntilStarted()
    try await waitForCompletedDownloadLoadCount(1, fixture: fixture)
    let placeholderRows: Set<String> = [
      "completed-volume-job", "queued-volume-job", "pending-\(entry.id)",
    ]
    try await waitForDisplayedIDs(placeholderRows, in: controller.downloadsController)
    let loadsBeforeRelease = await fixture.loadCount()
    await fixture.delayNextLoad()

    // Act: enqueue returns, but its follow-up snapshot is still loading.
    await enqueueGate.release(1)
    try await waitForDownloadLoadCount(loadsBeforeRelease + 1, fixture: fixture)

    // Assert: the placeholder is not dropped before a snapshot replaces it.
    #expect(Set(controller.downloadsController.displayedEntries.map(\.id)) == placeholderRows)
    await fixture.releaseDelayedLoad()
    try await waitForDisplayedIDs(
      ["completed-volume-job", "queued-volume-job"],
      in: controller.downloadsController
    )

    controller.showAllItems(nil)
  }
}

@MainActor
@Test(.sourceEnglish)
func packageDownloadIsQueuedWhileAnUpdateLookupForTheSameEntryIsPending() async throws {
  // Arrange
  let lookup = SlowUpdateLookup()
  let controller = BrowserViewController(dataSource: SlowUpdateDataSource(lookup: lookup))
  _ = controller.view
  let game = browserEntry(id: "catalogue-PCSA00008", title: "Update And Game")
  controller.enqueueUpdate(game)
  await lookup.waitUntilStarted()

  // Act
  controller.showAllItems(nil)
  controller.enqueue(game)

  // Assert: both requests keep their own placeholder, added synchronously.
  let displayedIDs = Set(controller.downloadsController.displayedEntries.map(\.id))
  #expect(displayedIDs == ["pending-update-\(game.id)", "pending-\(game.id)"])
  if displayedIDs.contains("pending-\(game.id)") {
    await lookup.waitUntilNormalEnqueueStarted()
    await lookup.finishNormalEnqueue(with: [])
  }
  await lookup.finish(with: [])
}

@MainActor
@Test(.sourceEnglish)
func pendingUpdateLookupSurvivesEmptySnapshotsUntilTheJobExists() async throws {
  let lookup = SlowUpdateLookup()
  let controller = BrowserViewController(dataSource: SlowUpdateDataSource(lookup: lookup))
  _ = controller.view
  let game = browserEntry(id: "catalogue-PCSA00007", title: "Example Vita Game")

  controller.enqueueUpdate(game)
  await lookup.waitUntilStarted()
  await controller.reloadDownloads()

  #expect(
    controller.downloadsController.displayedEntries.map(\.id) == ["pending-update-\(game.id)"]
  )
  #expect(
    controller.downloadsController.displayedEntries.first?.title == "Example Vita Game Update"
  )

  let realJob = DownloadEntry(
    id: "download-job-1",
    title: "Example Vita Game Update",
    detail: "PCSA00007 · 0 bytes",
    state: .queued,
    progress: 0,
    completedFile: nil,
    titleID: game.titleID,
    createdAt: Date(),
    canPause: true
  )
  await lookup.finish(with: [realJob])

  for _ in 0..<100 {
    if controller.downloadsController.displayedEntries.map(\.id) == [realJob.id] { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  #expect(controller.downloadsController.displayedEntries.map(\.id) == [realJob.id])
}

@MainActor
@Test(.sourceEnglish)
func pendingUpdateLookupIsRemovedAfterLookupFailure() async throws {
  let lookup = SlowUpdateLookup()
  let controller = BrowserViewController(dataSource: SlowUpdateDataSource(lookup: lookup))
  _ = controller.view
  var presentedError = false
  controller.onError = { _ in presentedError = true }
  let game = browserEntry(id: "catalogue-PCSA00007", title: "Example Vita Game")

  controller.enqueueUpdate(game)
  await lookup.waitUntilStarted()
  await controller.reloadDownloads()
  #expect(
    controller.downloadsController.displayedEntries.map(\.id) == ["pending-update-\(game.id)"]
  )

  await lookup.fail(TestError.lookupFailed)
  for _ in 0..<100 {
    if presentedError && controller.downloadsController.displayedEntries.isEmpty { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  #expect(presentedError)
  #expect(controller.downloadsController.displayedEntries.isEmpty)
}

@MainActor
@Test(.sourceEnglish)
func normalEnqueueKeepsExistingJobsAndPendingRequestVisible() async throws {
  let existing = DownloadEntry(
    id: "existing-job",
    title: "Existing Game",
    detail: "PCSB00001",
    state: .complete,
    progress: 1,
    completedFile: nil,
    titleID: "PCSB00001",
    createdAt: Date().addingTimeInterval(-60)
  )
  let lookup = SlowUpdateLookup(downloads: [existing])
  let controller = BrowserViewController(dataSource: SlowUpdateDataSource(lookup: lookup))
  _ = controller.view
  await controller.reloadDownloads()
  let game = browserEntry(id: "catalogue-PCSA00007", title: "New Vita Game")

  controller.enqueue(game)
  await lookup.waitUntilNormalEnqueueStarted()
  await controller.reloadDownloads()

  #expect(
    controller.downloadsController.displayedEntries.map(\.id) == [
      existing.id, "pending-\(game.id)",
    ]
  )
  #expect(controller.downloadsController.displayedEntries.first?.title == existing.title)

  let newJob = DownloadEntry(
    id: "new-download-job",
    title: game.title,
    detail: "PCSA00007 · 0 bytes",
    state: .queued,
    progress: 0,
    completedFile: nil,
    titleID: game.titleID,
    createdAt: Date(),
    canPause: true
  )
  await lookup.finishNormalEnqueue(with: [existing, newJob])

  for _ in 0..<100 {
    if controller.downloadsController.displayedEntries.map(\.id) == [existing.id, newJob.id] {
      break
    }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  #expect(controller.downloadsController.displayedEntries.map(\.id) == [existing.id, newJob.id])
}

@MainActor
@Test(.sourceEnglish)
func pendingPatchEntryClearsWhenCompositeJobUsesPackTitle() async throws {
  let lookup = SlowUpdateLookup()
  let controller = BrowserViewController(dataSource: SlowUpdateDataSource(lookup: lookup))
  _ = controller.view
  let patchEntry = BrowserEntry(
    id: "patch-PCSB01101",
    title: "Example Patch Name",
    titleID: "PCSB01101",
    console: "PS Vita",
    consoleCode: "PSV",
    category: "CPatch",
    region: "",
    fileSize: nil,
    packageURL: URL(string: "http://127.0.0.1:1/patch.ppk"),
    sha256: nil,
    contentID: nil,
    isCompatibilityPack: true,
    compatibilityPackKind: .patch,
    matchingPackURL: URL(string: "http://127.0.0.1:1/pack.ppk"),
    matchingPackTitle: "Example Base Pack"
  )

  controller.enqueue(patchEntry)
  await lookup.waitUntilNormalEnqueueStarted()
  await controller.reloadDownloads()
  #expect(controller.downloadsController.displayedEntries.map(\.id) == ["pending-\(patchEntry.id)"])

  let compositeJob = DownloadEntry(
    id: "composite-job",
    title: "Example Base Pack",
    detail: "PCSB01101 · 0 bytes",
    state: .queued,
    progress: 0,
    completedFile: nil,
    titleID: "PCSB01101",
    createdAt: Date(),
    canPause: true
  )
  await lookup.finishNormalEnqueue(with: [compositeJob])

  for _ in 0..<100 {
    if controller.downloadsController.displayedEntries.map(\.id) == [compositeJob.id] { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  #expect(controller.downloadsController.displayedEntries.map(\.id) == [compositeJob.id])
}
