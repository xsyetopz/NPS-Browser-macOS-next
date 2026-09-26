import AppKit
import Foundation
import Testing
@testable import NPSBrowserApp

extension BrowserViewControllerTests {
  @Test
  func volumeNotificationsRefreshRevealAndPreserveSelectionAndPendingJobs() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSBrowser-volume-refresh-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let extractedDirectory = temporaryRoot.appendingPathComponent(
      "MountedLibrary/Game [PCSE12345]",
      isDirectory: true
    )
    let fixture = WorkspaceVolumeSnapshotFixture(extractedDirectory: extractedDirectory)
    let enqueueGate = WorkspaceEnqueueGate()
    let source = WorkspaceVolumeBrowserDataSource(fixture: fixture, enqueueGate: enqueueGate)
    let notifications = NotificationCenter()
    let controller = BrowserViewController(
      dataSource: source,
      workspaceNotificationCenter: notifications
    )
    _ = controller.view

    let catalogueEntry = workspaceRefreshCatalogueEntry()
    controller.enqueue(catalogueEntry)
    await enqueueGate.waitUntilStarted()
    try await waitForDownloadLoadCount(1, fixture: fixture)
    try await waitForDisplayedIDs(
      ["completed-volume-job", "queued-volume-job", "pending-\(catalogueEntry.id)"],
      in: controller.downloadsController
    )

    let downloads = controller.downloadsController
    downloads.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    #expect(downloads.selectedEntry?.id == "completed-volume-job")
    #expect(try !#require(downloads.displayedEntries.first).canPerform(.reveal))

    try FileManager.default.createDirectory(
      at: extractedDirectory,
      withIntermediateDirectories: true
    )
    notifications.post(name: NSWorkspace.didMountNotification, object: nil)
    try await waitForDownloadLoadCount(2, fixture: fixture)
    try await waitForRevealAvailability(true, in: downloads)
    #expect(downloads.selectedEntry?.id == "completed-volume-job")
    #expect(downloads.displayedEntries.contains { $0.id == "pending-\(catalogueEntry.id)" })

    try FileManager.default.removeItem(at: temporaryRoot)
    notifications.post(name: NSWorkspace.didUnmountNotification, object: nil)
    try await waitForDownloadLoadCount(3, fixture: fixture)
    try await waitForRevealAvailability(false, in: downloads)
    #expect(downloads.selectedEntry?.id == "completed-volume-job")
    #expect(downloads.displayedEntries.contains { $0.id == "pending-\(catalogueEntry.id)" })

    let navigationController = try #require(
      controller.children.compactMap { $0 as? NSSplitViewController }.first?.splitViewItems.first?
        .viewController as? NavigationViewController
    )
    navigationController.select(.allItems)
    let loadsAfterLeavingDownloads = await fixture.loadCount()
    notifications.post(name: NSWorkspace.didMountNotification, object: nil)
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(await fixture.loadCount() == loadsAfterLeavingDownloads)

    await enqueueGate.release()
    try await waitForDownloadLoadCount(loadsAfterLeavingDownloads + 1, fixture: fixture)
  }

  @Test
  func latestVolumeSnapshotWinsWhenEarlierLoadReturnsLast() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSBrowser-volume-order-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let extractedDirectory = temporaryRoot.appendingPathComponent(
      "MountedLibrary/Game [PCSE12345]",
      isDirectory: true
    )
    let fixture = WorkspaceVolumeSnapshotFixture(extractedDirectory: extractedDirectory)
    let source = WorkspaceVolumeBrowserDataSource(
      fixture: fixture,
      enqueueGate: WorkspaceEnqueueGate()
    )
    let controller = BrowserViewController(dataSource: source)
    _ = controller.downloadsController.view

    await controller.reloadDownloads()
    #expect(
      try !#require(controller.downloadsController.displayedEntries.first).canPerform(.reveal)
    )

    try FileManager.default.createDirectory(
      at: extractedDirectory,
      withIntermediateDirectories: true
    )
    await fixture.delayNextLoad()
    let olderMountReload = Task { await controller.reloadDownloads() }
    try await waitForDownloadLoadCount(2, fixture: fixture)

    try FileManager.default.removeItem(at: temporaryRoot)
    let newerUnmountReload = Task { await controller.reloadDownloads() }
    try await waitForDownloadLoadCount(3, fixture: fixture)
    await newerUnmountReload.value
    #expect(
      try !#require(controller.downloadsController.displayedEntries.first).canPerform(.reveal)
    )

    await fixture.releaseDelayedLoad()
    await olderMountReload.value
    #expect(
      try !#require(controller.downloadsController.displayedEntries.first).canPerform(.reveal)
    )
  }

  @Test
  func bufferedStreamSnapshotReloadsAfterMountInsteadOfRestoringStaleRevealState() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSBrowser-volume-stream-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let extractedDirectory = temporaryRoot.appendingPathComponent(
      "MountedLibrary/Game [PCSE12345]",
      isDirectory: true
    )
    let fixture = WorkspaceVolumeSnapshotFixture(extractedDirectory: extractedDirectory)
    let notifications = NotificationCenter()
    let source = WorkspaceVolumeBrowserDataSource(
      fixture: fixture,
      enqueueGate: WorkspaceEnqueueGate()
    )
    let controller = BrowserViewController(
      dataSource: source,
      workspaceNotificationCenter: notifications
    )
    _ = controller.view
    controller.showDownloads(nil)
    try await waitForDownloadLoadCount(1, fixture: fixture)
    try await waitForStreamObserverCount(1, fixture: fixture)
    try await waitForRevealAvailability(false, in: controller.downloadsController)

    try FileManager.default.createDirectory(
      at: extractedDirectory,
      withIntermediateDirectories: true
    )
    notifications.post(name: NSWorkspace.didMountNotification, object: nil)
    try await waitForDownloadLoadCount(2, fixture: fixture)
    try await waitForRevealAvailability(true, in: controller.downloadsController)

    await fixture.replaceDownloads([
      DownloadEntry(
        id: "completed-volume-job",
        title: "Completed Game",
        detail: "authoritative snapshot after mount",
        state: .complete,
        progress: 1,
        completedFile: extractedDirectory,
        titleID: "PCSE12345"
      )
    ])
    await fixture.emit([
      DownloadEntry(
        id: "completed-volume-job",
        title: "Completed Game",
        detail: "stale buffered stream snapshot",
        state: .complete,
        progress: 1,
        completedFile: nil,
        titleID: "PCSE12345"
      )
    ])
    try await waitForDownloadLoadCount(3, fixture: fixture)
    try await waitForDownloadDetail(
      "authoritative snapshot after mount",
      in: controller.downloadsController
    )
    try await waitForRevealAvailability(true, in: controller.downloadsController)

    controller.showAllItems(nil)
  }

  @Test
  func reenteringDownloadsWithholdsCachedRevealUntilTheFreshSnapshot() async throws {
    // Arrange: Reveal is available, then the volume goes away while Downloads is hidden.
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSBrowser-reveal-reentry-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let extractedDirectory = temporaryRoot.appendingPathComponent(
      "Library/Game [PCSE12345]",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: extractedDirectory,
      withIntermediateDirectories: true
    )
    let fixture = WorkspaceVolumeSnapshotFixture(extractedDirectory: extractedDirectory)
    let source = WorkspaceVolumeBrowserDataSource(
      fixture: fixture,
      enqueueGate: WorkspaceEnqueueGate()
    )
    let controller = BrowserViewController(
      dataSource: source,
      workspaceNotificationCenter: NotificationCenter()
    )
    _ = controller.view
    let downloads = controller.downloadsController
    controller.showDownloads(nil)
    try await waitForRevealAvailability(true, in: downloads)
    controller.showAllItems(nil)
    try FileManager.default.removeItem(at: temporaryRoot)
    let loadsBeforeReentry = await fixture.loadCount()
    await fixture.delayNextLoad()

    // Act
    controller.showDownloads(nil)
    try await waitForDownloadLoadCount(loadsBeforeReentry + 1, fixture: fixture)

    // Assert: the cached row is shown without Reveal while the snapshot loads.
    let cached = try #require(downloads.displayedEntries.first { $0.id == "completed-volume-job" })
    #expect(!cached.canPerform(.reveal))
    await fixture.releaseDelayedLoad()
    try await waitForCompletedDownloadLoadCount(loadsBeforeReentry + 1, fixture: fixture)
    try await waitForRevealAvailability(false, in: downloads)

    controller.showAllItems(nil)
  }

  @Test
  func leavingDownloadsDuringInitialLoadDoesNotStartItsStreamObserver() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSBrowser-download-lifecycle-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let extractedDirectory = temporaryRoot.appendingPathComponent(
      "MountedLibrary",
      isDirectory: true
    )
    let fixture = WorkspaceVolumeSnapshotFixture(extractedDirectory: extractedDirectory)
    let source = WorkspaceVolumeBrowserDataSource(
      fixture: fixture,
      enqueueGate: WorkspaceEnqueueGate()
    )
    let controller = BrowserViewController(dataSource: source)
    _ = controller.view

    await fixture.delayNextLoad()
    controller.showDownloads(nil)
    try await waitForDownloadLoadCount(1, fixture: fixture)
    controller.showAllItems(nil)

    await fixture.releaseDelayedLoad()
    try await waitForCompletedDownloadLoadCount(1, fixture: fixture)
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(await fixture.streamObserverCount() == 0)
  }
}

@MainActor
@Test(.sourceEnglish)
func activeRemovalNeedsConsequenceConfirmationButCompletedRemovalDoesNot() async throws {
  let queued = DownloadEntry(
    id: "active-removal",
    title: "Queued Game",
    detail: "PCSA00001 · 0 bytes",
    state: .queued,
    progress: 0,
    completedFile: nil,
    canPause: true
  )
  let lookup = SlowUpdateLookup(downloads: [queued])
  let controller = BrowserViewController(dataSource: SlowUpdateDataSource(lookup: lookup))
  _ = controller.view
  controller.showDownloads(nil)
  await controller.reloadDownloads()
  controller.downloadsController.tableView.selectRowIndexes(
    IndexSet(integer: 0),
    byExtendingSelection: false
  )

  var presentedAlert: NSAlert?
  var answer: ((Bool) -> Void)?
  var prompts = 0
  controller.activeRemovalConfirmationPresenter = { alert, entry, resolve in
    prompts += 1
    #expect(entry.id == queued.id)
    presentedAlert = alert
    answer = resolve
  }
  controller.removeSelectedDownload(nil)

  let alert = try #require(presentedAlert)
  #expect(alert.alertStyle == .warning)
  #expect(alert.messageText.isEmpty == false)
  #expect(alert.informativeText.contains(queued.title))
  #expect(alert.informativeText.localizedCaseInsensitiveContains("cancels the transfer"))
  #expect(alert.informativeText.localizedCaseInsensitiveContains("resume information"))
  #expect(alert.buttons.map(\.title) == ["Cancel", "Remove Download"])
  #expect(await lookup.controlCount() == 0)

  let confirm = try #require(answer)
  confirm(false)
  try await Task.sleep(nanoseconds: 20_000_000)
  #expect(await lookup.controlCount() == 0)

  let activity = controller.downloadsController
  let actionsColumn = try #require(
    activity.tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("actions"))
  )
  let activeCell = try #require(
    activity.tableView(activity.tableView, viewFor: actionsColumn, row: 0)
  )
  let rowRemove = try #require(
    nestedAppKitViews(of: activeCell).compactMap { $0 as? NSButton }.first {
      $0.tag == DownloadAction.remove.rawValue
    }
  )
  rowRemove.performClick(nil)
  #expect(prompts == 2)
  let cancelRowRemoval = try #require(answer)
  cancelRowRemoval(false)
  #expect(await lookup.controlCount() == 0)

  controller.removeSelectedDownload(nil)
  #expect(prompts == 3)
  let confirmRemoval = try #require(answer)
  confirmRemoval(true)
  await lookup.waitForControlCount(1)
  #expect(await lookup.controlCount() == 1)

  let completed = DownloadEntry(
    id: "completed-removal",
    title: "Completed Game",
    detail: "PCSA00002 · 42 MB",
    state: .complete,
    progress: 1,
    completedFile: URL(fileURLWithPath: "/tmp/completed.pkg")
  )
  controller.downloadsController.setEntries([completed])
  controller.downloadsController.tableView.selectRowIndexes(
    IndexSet(integer: 0),
    byExtendingSelection: false
  )
  controller.removeSelectedDownload(nil)
  await lookup.waitForControlCount(2)
  #expect(prompts == 3)
  #expect(await lookup.controlCount() == 2)
}

@MainActor
@Test(.sourceEnglish)
func downloadMenuActionsCannotOperateOnHiddenSelection() async throws {
  let downloading = DownloadEntry(
    id: "active-job",
    title: "Example",
    detail: "PCSA00007",
    state: .downloading,
    progress: 0.5,
    completedFile: nil,
    canPause: true
  )
  let lookup = SlowUpdateLookup(downloads: [downloading])
  let target = BrowserViewController(dataSource: SlowUpdateDataSource(lookup: lookup))
  _ = target.view
  target.showDownloads(nil)
  await target.reloadDownloads()
  target.downloadsController.tableView.selectRowIndexes(
    IndexSet(integer: 0),
    byExtendingSelection: false
  )

  #expect(
    target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.pauseSelectedDownload(_:)))
    )
  )
  target.pauseSelectedDownload(nil)
  await lookup.waitForControlCount(1)
  #expect(await lookup.controlCount() == 1)

  target.showAllItems(nil)
  #expect(
    !target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.pauseSelectedDownload(_:)))
    )
  )
  target.pauseSelectedDownload(nil)
  try await Task.sleep(nanoseconds: 50_000_000)
  #expect(await lookup.controlCount() == 1)
}

@MainActor
private func nestedAppKitViews(of view: NSView) -> [NSView] {
  [view] + view.subviews.flatMap(nestedAppKitViews)
}
