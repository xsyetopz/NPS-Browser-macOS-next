import AppKit
import Foundation
import Testing
@testable import NPSBrowserApp

@MainActor
@Test(.sourceEnglish)
func downloadActivityMenuBarExposesAndValidatesSelectedJobActions() {
  let target = BrowserViewController(dataSource: EmptyBrowserDataSource())
  _ = NSApplication.shared  // creates NSApp regardless of test order
  let previousMenu = NSApp.mainMenu
  defer { NSApp.mainMenu = previousMenu }
  _ = target.view

  AppDelegate().buildMainMenu(target: target)

  let expectedActions: Set<String> = [
    NSStringFromSelector(#selector(BrowserViewController.pauseSelectedDownload(_:))),
    NSStringFromSelector(#selector(BrowserViewController.resumeSelectedDownload(_:))),
    NSStringFromSelector(#selector(BrowserViewController.restartSelectedDownload(_:))),
    NSStringFromSelector(#selector(BrowserViewController.retryExtractionSelectedDownload(_:))),
    NSStringFromSelector(#selector(BrowserViewController.removeSelectedDownload(_:))),
    NSStringFromSelector(#selector(BrowserViewController.revealSelectedDownload(_:))),
  ]
  let activityMenu = findMenu(containingActions: expectedActions, in: NSApp.mainMenu)
  #expect(
    Set(activityMenu?.items.compactMap(\.action).map(NSStringFromSelector) ?? []) == expectedActions
  )

  let activity = target.downloadsController
  _ = activity.view
  let downloading = DownloadEntry(
    id: "downloading",
    title: "Example",
    detail: "PCSA00007",
    state: .downloading,
    progress: 0.5,
    completedFile: nil,
    canPause: true
  )
  activity.setEntries([downloading])
  activity.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

  #expect(
    !target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.pauseSelectedDownload(_:)))
    )
  )
  target.showDownloads(nil)
  activity.setEntries([downloading])
  activity.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  #expect(target.canPerformSelectedDownloadAction(.pause))
  #expect(!target.canPerformSelectedDownloadAction(.resume))
  #expect(target.canPerformSelectedDownloadAction(.remove))
  #expect(!target.canPerformSelectedDownloadAction(.reveal))
  #expect(
    target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.pauseSelectedDownload(_:)))
    )
  )
  #expect(
    !target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.resumeSelectedDownload(_:)))
    )
  )
  #expect(
    !target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.retryExtractionSelectedDownload(_:)))
    )
  )
  #expect(
    target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.removeSelectedDownload(_:)))
    )
  )
  #expect(
    !target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.revealSelectedDownload(_:)))
    )
  )

  activity.setEntries([
    DownloadEntry(
      id: "extracting",
      title: "Example",
      detail: "PCSA00007",
      state: .extracting,
      progress: nil,
      completedFile: nil,
      canRemove: false
    )
  ])
  activity.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  #expect(!target.canPerformSelectedDownloadAction(.remove))
  #expect(
    !target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.removeSelectedDownload(_:)))
    )
  )

  let failedExtraction = DownloadEntry(
    id: "failed-extraction",
    title: "Example",
    detail: "Extraction failed",
    state: .failed,
    progress: 1,
    completedFile: URL(fileURLWithPath: "/tmp/verified-example.pkg"),
    canRestart: true,
    canRetryExtraction: true
  )
  activity.setEntries([failedExtraction])
  activity.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  #expect(
    target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.restartSelectedDownload(_:)))
    )
  )
  #expect(
    target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.retryExtractionSelectedDownload(_:)))
    )
  )
  #expect(
    target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.revealSelectedDownload(_:)))
    )
  )

  target.showAllItems(nil)
  #expect(
    !target.validateMenuItem(
      menuItem(action: #selector(BrowserViewController.retryExtractionSelectedDownload(_:)))
    )
  )
}

@MainActor
@Test(.sourceEnglish)
func RAPOnlyEntriesOfferRAPButNotPackageDownloadInInspectorMenuAndContext() {
  let rapURL = URL(
    string: "https://nopaystation.com/tools/rap2file/UP0001-NPUB12345_00-EXAMPLE000000000/NPUB12345"
  )!
  let ps3 = rapEntry(
    console: "PS3",
    consoleCode: "PS3",
    titleID: "NPUB12345",
    rapURL: rapURL,
    packageURL: nil
  )
  let vita = rapEntry(console: "PS Vita", consoleCode: "PSV", titleID: "PCSA00007", rapURL: rapURL)
  let unsafeID = rapEntry(
    console: "PS3",
    consoleCode: "PS3",
    titleID: "../NPUB12345",
    rapURL: rapURL
  )

  #expect(ps3.supportsRAPDownload)
  #expect(!ps3.supportsPackageDownload)
  #expect(
    !rapEntry(
      console: "PS3",
      consoleCode: "PS3",
      titleID: "NPUB12345",
      rapURL: rapURL,
      packageURL: URL(string: "file:///tmp/game.pkg")
    ).supportsPackageDownload
  )
  #expect(!vita.supportsRAPDownload)
  #expect(!unsafeID.supportsRAPDownload)

  let inspector = ItemInspectorViewController()
  _ = inspector.view
  inspector.show(entry: ps3, bookmarked: false)
  #expect(!inspector.isPackageDownloadButtonVisible)
  #expect(inspector.isRAPDownloadButtonVisible)
  inspector.show(entry: vita, bookmarked: false)
  #expect(inspector.isPackageDownloadButtonVisible)
  #expect(!inspector.isRAPDownloadButtonVisible)
  inspector.show(entry: nil, bookmarked: false)
  #expect(!inspector.isPackageDownloadButtonVisible)
  #expect(!inspector.isRAPDownloadButtonVisible)

  _ = NSApplication.shared  // creates NSApp regardless of test order
  let previousMenu = NSApp.mainMenu
  defer { NSApp.mainMenu = previousMenu }
  let controller = BrowserViewController(dataSource: EmptyBrowserDataSource())
  _ = controller.view
  AppDelegate().buildMainMenu(target: controller)
  controller.catalogueController.setEntries([ps3])
  controller.catalogueController.tableView.selectRowIndexes(
    IndexSet(integer: 0),
    byExtendingSelection: false
  )

  let action = #selector(BrowserViewController.downloadRAPSelected(_:))
  let menuItem = NSMenuItem(title: "", action: action, keyEquivalent: "")
  #expect(controller.validateMenuItem(menuItem))
  let packageDownloadAction = #selector(BrowserViewController.downloadSelected(_:))
  let packageMenuItem = NSMenuItem(
    title: "Download",
    action: packageDownloadAction,
    keyEquivalent: ""
  )
  let packageToolbarItem = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("test.download"))
  packageToolbarItem.action = packageDownloadAction
  #expect(!controller.validateMenuItem(packageMenuItem))
  #expect(!controller.validateToolbarItem(packageToolbarItem))
  controller.showDownloads(nil)
  #expect(!controller.validateMenuItem(menuItem))
  controller.showAllItems(nil)
  let fileMenu = NSApp.mainMenu?.items.compactMap(\.submenu).first { menu in
    menu.items.contains { $0.action == action }
  }
  #expect(fileMenu?.items.contains { $0.action == action && $0.title == "Download RAP" } == true)

  let contextMenu = NSMenu()
  controller.catalogueController.configureContextMenu(contextMenu, for: ps3)
  #expect(!contextMenu.items.contains { $0.title == "Download" })
  let rapContextItem = contextMenu.items.first { $0.title == "Download RAP" }
  #expect(rapContextItem?.action == #selector(CatalogTableViewController.contextDownloadRAP(_:)))
  var requestedEntryID: String?
  controller.catalogueController.onDownloadRAP = { requestedEntryID = $0.id }
  controller.catalogueController.contextDownloadRAP(rapContextItem)
  #expect(requestedEntryID == ps3.id)

  let packageEntry = rapEntry(
    console: "PS3",
    consoleCode: "PS3",
    titleID: "NPUB12345",
    rapURL: rapURL
  )
  controller.catalogueController.setEntries([packageEntry])
  controller.catalogueController.tableView.selectRowIndexes(
    IndexSet(integer: 0),
    byExtendingSelection: false
  )
  #expect(controller.validateMenuItem(packageMenuItem))
  #expect(controller.validateToolbarItem(packageToolbarItem))
  let packageContextMenu = NSMenu()
  controller.catalogueController.configureContextMenu(packageContextMenu, for: packageEntry)
  #expect(packageContextMenu.items.contains { $0.title == "Download" })

  let vitaContextMenu = NSMenu()
  controller.catalogueController.configureContextMenu(vitaContextMenu, for: vita)
  #expect(!vitaContextMenu.items.contains { $0.title == "Download RAP" })
  controller.catalogueController.setEntries([vita])
  controller.catalogueController.tableView.selectRowIndexes(
    IndexSet(integer: 0),
    byExtendingSelection: false
  )
  #expect(!controller.validateMenuItem(menuItem))
}

@MainActor
private func findMenu(containingActions expected: Set<String>, in menu: NSMenu?) -> NSMenu? {
  guard let menu else { return nil }
  for item in menu.items {
    guard let submenu = item.submenu else { continue }
    let actions = Set(submenu.items.compactMap(\.action).map(NSStringFromSelector))
    if actions == expected { return submenu }
    if let found = findMenu(containingActions: expected, in: submenu) { return found }
  }
  return nil
}

private func rapEntry(
  console: String,
  consoleCode: String,
  titleID: String,
  rapURL: URL,
  packageURL: URL? = URL(string: "https://example.test/game.pkg")
) -> BrowserEntry {
  BrowserEntry(
    id: "\(consoleCode)-\(titleID)",
    title: "Example Game",
    titleID: titleID,
    console: console,
    consoleCode: consoleCode,
    category: "Game",
    region: "US",
    fileSize: nil,
    packageURL: packageURL,
    rapDownloadURL: rapURL,
    sha256: nil,
    contentID: nil
  )
}
