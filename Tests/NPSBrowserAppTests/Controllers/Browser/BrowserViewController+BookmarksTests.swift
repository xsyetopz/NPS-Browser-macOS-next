import AppKit
import Foundation
import NPSBrowserAppResources
import Testing
@testable import NPSBrowserApp

@MainActor
@Test(.sourceEnglish)
func failedBookmarkWriteKeepsTheNewlySelectedInspectorEntry() async throws {
  let first = bookmarkRegressionEntry(id: "bookmark-first", title: "First Game")
  let second = bookmarkRegressionEntry(id: "bookmark-second", title: "Second Game")
  let gate = DelayedBookmarkFailureGate()
  let dataSource = DelayedBookmarkFailureDataSource(entries: [first, second], gate: gate)
  let controller = BrowserViewController(dataSource: dataSource)
  var reportedError: String?
  controller.onError = { reportedError = $0 }
  _ = controller.view

  let table = controller.catalogueController.tableView
  for _ in 0..<100 {
    if controller.catalogueController.numberOfRows(in: table) == 2 { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  #expect(controller.catalogueController.numberOfRows(in: table) == 2)

  let inspector = try #require(
    controller.children.compactMap { $0 as? NSSplitViewController }.first?.splitViewItems.last?
      .viewController as? ItemInspectorViewController
  )
  table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  #expect(controller.catalogueController.selectedEntry?.id == first.id)
  #expect(inspector.currentEntry?.id == first.id)

  controller.toggleBookmark(nil)
  await gate.waitForWrite(1)
  table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
  #expect(controller.catalogueController.selectedEntry?.id == second.id)
  #expect(inspector.currentEntry?.id == second.id)

  await gate.releaseWrite(1)
  for _ in 0..<100 {
    if reportedError != nil { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  #expect(reportedError != nil)
  #expect(controller.catalogueController.selectedEntry?.id == second.id)
  #expect(inspector.currentEntry?.id == second.id)
  #expect(inspector.currentEntry?.title == "Second Game")
}

@MainActor
@Test(.sourceEnglish)
func rapidAddThenRemoveWithBothWritesFailReconcilesToPersistedState() async throws {
  let entry = bookmarkRegressionEntry(id: "bookmark-overlap", title: "Overlapping Game")
  let gate = DelayedBookmarkFailureGate()
  let dataSource = DelayedBookmarkFailureDataSource(entries: [entry], gate: gate)
  let controller = BrowserViewController(dataSource: dataSource)
  var reportedError: String?
  controller.onError = { reportedError = $0 }
  _ = controller.view
  let table = controller.catalogueController.tableView
  for _ in 0..<100 {
    if controller.catalogueController.numberOfRows(in: table) == 1 { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  let inspector = try #require(inspectorController(of: controller))
  table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  #expect(inspector.currentEntry?.id == entry.id)

  controller.toggleBookmark(nil)
  controller.toggleBookmark(nil)
  #expect(bookmarkButton(in: inspector)?.title == AppResources.localized("action.bookmark.add"))

  await gate.waitForWrite(1)
  await gate.releaseWrite(1)
  await gate.waitForWrite(2)
  await gate.releaseWrite(2)
  for _ in 0..<100 {
    if reportedError != nil { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  #expect(reportedError != nil)
  #expect(controller.catalogueController.selectedEntry?.id == entry.id)
  #expect(inspector.currentEntry?.id == entry.id)
  #expect(bookmarkButton(in: inspector)?.title == AppResources.localized("action.bookmark.add"))
}

@MainActor
@Test(.sourceEnglish)
func failedBookmarkRemovalRestoresBookmarksSelectionWhenUserHasNotMoved() async throws {
  let first = bookmarkRegressionEntry(id: "bookmark-first", title: "First Game")
  let second = bookmarkRegressionEntry(id: "bookmark-second", title: "Second Game")
  let harness = try await makeBookmarkFilterHarness(entries: [first, second])
  var reportedError: String?
  harness.controller.onError = { reportedError = $0 }
  harness.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  #expect(harness.controller.catalogueController.selectedEntry?.id == first.id)
  #expect(harness.inspector.currentEntry?.id == first.id)

  harness.controller.toggleBookmark(nil)
  #expect(harness.controller.catalogueController.selectedEntry == nil)
  await harness.gate.waitForWrite(1)
  await harness.gate.releaseWrite(1)
  for _ in 0..<100 {
    if reportedError != nil { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  #expect(reportedError != nil)
  #expect(harness.controller.catalogueController.numberOfRows(in: harness.table) == 2)
  #expect(harness.controller.catalogueController.selectedEntry?.id == first.id)
  #expect(harness.inspector.currentEntry?.id == first.id)
  #expect(
    bookmarkButton(in: harness.inspector)?.title == AppResources.localized("action.bookmark.remove")
  )
}

@MainActor
@Test(.sourceEnglish)
func failedBookmarkRemovalDoesNotReplaceASelectionMadeDuringTheWrite() async throws {
  let first = bookmarkRegressionEntry(id: "bookmark-first", title: "First Game")
  let second = bookmarkRegressionEntry(id: "bookmark-second", title: "Second Game")
  let harness = try await makeBookmarkFilterHarness(entries: [first, second])
  var reportedError: String?
  harness.controller.onError = { reportedError = $0 }
  harness.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  harness.controller.toggleBookmark(nil)
  await harness.gate.waitForWrite(1)

  harness.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  #expect(harness.controller.catalogueController.selectedEntry?.id == second.id)
  await harness.gate.releaseWrite(1)
  for _ in 0..<100 {
    if reportedError != nil { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  #expect(reportedError != nil)
  #expect(harness.controller.catalogueController.numberOfRows(in: harness.table) == 2)
  #expect(harness.controller.catalogueController.selectedEntry?.id == second.id)
  #expect(harness.inspector.currentEntry?.id == second.id)
}

@MainActor
@Test(.sourceEnglish)
func failedBookmarkRemovalRespectsAnExplicitNilSelectionAfterAutomaticDeselect() async throws {
  let first = bookmarkRegressionEntry(id: "bookmark-first", title: "First Game")
  let second = bookmarkRegressionEntry(id: "bookmark-second", title: "Second Game")
  let harness = try await makeBookmarkFilterHarness(entries: [first, second])
  var reportedError: String?
  harness.controller.onError = { reportedError = $0 }
  harness.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  harness.controller.toggleBookmark(nil)
  await harness.gate.waitForWrite(1)
  #expect(harness.controller.catalogueController.selectedEntry == nil)

  // The first nil notification is the filter removing the unbookmarked row.
  // Deliver a later nil selection event to model a user explicitly keeping
  // the empty selection while the failed write is still pending.
  harness.controller.catalogueController.tableViewSelectionDidChange(
    Notification(name: NSTableView.selectionDidChangeNotification, object: harness.table)
  )
  await harness.gate.releaseWrite(1)
  for _ in 0..<100 {
    if reportedError != nil { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  #expect(reportedError != nil)
  #expect(harness.controller.catalogueController.numberOfRows(in: harness.table) == 2)
  #expect(harness.controller.catalogueController.selectedEntry == nil)
  #expect(harness.inspector.currentEntry == nil)
}

@MainActor
@Test(.sourceEnglish)
func failedBookmarkRemovalRestoresTheExactItemWhenVisibleFieldsAreDuplicated() async throws {
  let first = duplicateDisplayBookmark(id: "duplicate-first", contentID: "CONTENT-A")
  let second = duplicateDisplayBookmark(id: "duplicate-second", contentID: "CONTENT-B")
  let harness = try await makeBookmarkFilterHarness(entries: [first, second])
  var reportedError: String?
  harness.controller.onError = { reportedError = $0 }
  harness.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  #expect(harness.controller.catalogueController.selectedEntry?.id == first.id)
  harness.controller.toggleBookmark(nil)
  await harness.gate.waitForWrite(1)
  #expect(harness.controller.catalogueController.numberOfRows(in: harness.table) == 1)
  await harness.gate.releaseWrite(1)
  for _ in 0..<100 {
    if reportedError != nil { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  #expect(reportedError != nil)
  #expect(harness.controller.catalogueController.numberOfRows(in: harness.table) == 2)
  #expect(harness.controller.catalogueController.selectedEntry?.id == first.id)
  #expect(harness.inspector.currentEntry?.id == first.id)
}

private func bookmarkRegressionEntry(id: String, title: String) -> BrowserEntry {
  BrowserEntry(
    id: id,
    title: title,
    titleID: "NPUG1000\(id == "bookmark-first" ? "5" : "6")",
    console: "PlayStation Mobile",
    consoleCode: "PSM",
    category: "Game",
    region: "US",
    fileSize: nil,
    packageURL: URL(string: "https://example.test/\(id).pkg"),
    sha256: nil,
    contentID: nil
  )
}

private func duplicateDisplayBookmark(id: String, contentID: String) -> BrowserEntry {
  BrowserEntry(
    id: id,
    title: "Same Visible Name",
    titleID: "PCSE12345",
    console: "PS Vita",
    consoleCode: "PSV",
    category: "DLC",
    region: "US",
    fileSize: 2048,
    packageURL: URL(string: "https://example.test/\(contentID).pkg"),
    sha256: nil,
    contentID: contentID
  )
}

@MainActor
private struct BookmarkFilterHarness {
  let controller: BrowserViewController
  let table: NSTableView
  let inspector: ItemInspectorViewController
  let gate: DelayedBookmarkFailureGate
}

@MainActor
private func makeBookmarkFilterHarness(
  entries: [BrowserEntry]
) async throws -> BookmarkFilterHarness {
  let gate = DelayedBookmarkFailureGate()
  let dataSource = DelayedBookmarkFailureDataSource(
    entries: entries,
    gate: gate,
    initiallyBookmarkedIDs: Set(entries.map(\.id))
  )
  let controller = BrowserViewController(dataSource: dataSource)
  _ = controller.view
  let table = controller.catalogueController.tableView
  for _ in 0..<100 {
    if controller.catalogueController.numberOfRows(in: table) == entries.count { break }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  let splitController = try #require(
    controller.children.compactMap { $0 as? NSSplitViewController }.first
  )
  let navigationController = try #require(
    splitController.splitViewItems.first?.viewController as? NavigationViewController
  )
  _ = navigationController.view
  navigationController.select(.bookmarks)
  let inspector = try #require(inspectorController(of: controller))
  return BookmarkFilterHarness(
    controller: controller,
    table: table,
    inspector: inspector,
    gate: gate
  )
}

@MainActor
private func inspectorController(
  of controller: BrowserViewController
) -> ItemInspectorViewController? {
  controller.children.compactMap { $0 as? NSSplitViewController }.first?.splitViewItems.last?
    .viewController as? ItemInspectorViewController
}

@MainActor
private func bookmarkButton(in inspector: ItemInspectorViewController) -> NSButton? {
  descendants(of: inspector.view).compactMap { $0 as? NSButton }.first {
    $0.title == AppResources.localized("action.bookmark.add")
      || $0.title == AppResources.localized("action.bookmark.remove")
  }
}
