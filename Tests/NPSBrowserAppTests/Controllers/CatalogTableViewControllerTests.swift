import AppKit
import Foundation
import NPSCore
import NPSDownloads
import NPSPersistence
import Testing
@testable import NPSBrowserApp

@MainActor
@Test(.sourceEnglish)
func catalogueSortAndFilterPreserveSelectionByEntryIdentity() {
  let controller = CatalogTableViewController()
  let zulu = browserEntry(id: "zulu", title: "Zulu")
  let alpha = browserEntry(id: "alpha", title: "Alpha")
  controller.setEntries([zulu, alpha])
  _ = controller.view

  controller.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  #expect(controller.selectedEntry?.id == "zulu")

  controller.tableView.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
  controller.tableView(controller.tableView, sortDescriptorsDidChange: [])

  #expect(controller.tableView.selectedRow == 1)
  #expect(controller.selectedEntry?.id == "zulu")

  controller.search("Zulu")
  #expect(controller.tableView.selectedRow == 0)
  #expect(controller.selectedEntry?.id == "zulu")

  controller.search("Alpha")
  #expect(controller.selectedEntry == nil)
  #expect(controller.tableView.selectedRow == -1)
}

@MainActor
@Test(.sourceEnglish)
func bookmarksFilterAndSortByNameConsoleAndTitleIDPreservingSelection() {
  let controller = CatalogTableViewController()
  _ = controller.view
  let zeta = BrowserEntry(
    id: "zeta",
    title: "Zulu Game",
    titleID: "PCSE00003",
    console: "PS Vita",
    consoleCode: "PSV",
    category: "Game",
    region: "EU",
    fileSize: nil,
    packageURL: URL(string: "https://example.test/zeta.pkg"),
    sha256: nil,
    contentID: nil
  )
  let alpha = BrowserEntry(
    id: "alpha",
    title: "Alpha Game",
    titleID: "PCSE00002",
    console: "PS3",
    consoleCode: "PS3",
    category: "Game",
    region: "US",
    fileSize: nil,
    packageURL: URL(string: "https://example.test/alpha.pkg"),
    sha256: nil,
    contentID: nil
  )
  let bravo = BrowserEntry(
    id: "bravo",
    title: "Bravo Game",
    titleID: "PCSE00001",
    console: "PSP",
    consoleCode: "PSP",
    category: "Game",
    region: "JP",
    fileSize: nil,
    packageURL: URL(string: "https://example.test/bravo.pkg"),
    sha256: nil,
    contentID: nil
  )
  let unbookmarked = BrowserEntry(
    id: "unbookmarked",
    title: "Aardvark Game",
    titleID: "PCSE00000",
    console: "PS3",
    consoleCode: "PS3",
    category: "Game",
    region: "US",
    fileSize: nil,
    packageURL: URL(string: "https://example.test/unbookmarked.pkg"),
    sha256: nil,
    contentID: nil
  )
  let entries = [zeta, alpha, bravo, unbookmarked]
  controller.setEntries(entries)
  controller.setBookmarks([zeta.id, alpha.id, bravo.id])
  controller.show(section: .bookmarks)
  #expect(controller.numberOfRows(in: controller.tableView) == 3)

  func visibleIDs() -> [String] {
    (0..<controller.numberOfRows(in: controller.tableView)).compactMap { row in
      controller.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      return controller.selectedEntry?.id
    }
  }
  func select(_ id: String) {
    guard let row = visibleIDs().firstIndex(of: id) else {
      Issue.record("Expected bookmarked entry \(id) in the table")
      return
    }
    controller.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
  }
  func sort(_ key: String) {
    controller.tableView.sortDescriptors = [NSSortDescriptor(key: key, ascending: true)]
    controller.tableView(controller.tableView, sortDescriptorsDidChange: [])
  }

  select("alpha")
  sort("title")
  #expect(controller.selectedEntry?.id == "alpha")
  #expect(visibleIDs() == ["alpha", "bravo", "zeta"])

  select("alpha")
  sort("console")
  #expect(controller.selectedEntry?.id == "alpha")
  let expectedConsoleOrder = entries.filter { [zeta.id, alpha.id, bravo.id].contains($0.id) }.sorted
  { $0.console.localizedStandardCompare($1.console) == .orderedAscending }.map(\.id)
  #expect(visibleIDs() == expectedConsoleOrder)

  select("alpha")
  sort("titleID")
  #expect(controller.selectedEntry?.id == "alpha")
  #expect(visibleIDs() == ["bravo", "alpha", "zeta"])
  #expect(!visibleIDs().contains(unbookmarked.id))
}

@MainActor
@Test(.sourceEnglish)
func bothCatalogueAndDownloadTablesInstallNativeContextMenus() {
  let catalogueController = CatalogTableViewController()
  let downloadsController = DownloadActivityViewController()
  _ = catalogueController.view
  _ = downloadsController.view

  #expect(catalogueController.contextMenuInstalledOnTable)
  #expect(downloadsController.contextMenuInstalledOnTable)
}

@MainActor
@Test(.sourceEnglish)
func pcSF00403LiveDLCFixtureFlowsFromParserThroughTableAndInspector() async throws {
  let tsv = """
    Title ID\tRegion\tName\tPKG direct link\tzRIF\tContent ID\tLast Modification Date\tFile Size\
    \tSHA256
    PCSF00403\tEU\tKillzone Mercenary: M224-A1\
    \thttp://zeus.dl.playstation.net/cdn/EP9000/PCSF00243_00/lgcwNsJHZTQgiMykZGxVlZkbLZTOVBshAmpwuE\
    UqAOgcvRPiTeEDzQVvwqLuMLmU.pkg\
    \tKO5ifR1dQ+e7BlgiTDMyMQbZH2CAZKGxhQU+/z3YHF+SMu8zw7mjWokRX0NOj8b44AYAyloUewAA\
    \tEP9000-PCSF00243_00-P000000000001388\t2017-10-20 09:23:37\t102400\
    \td76cef6d10a5f3090ffd01a9821c5284cd42a1d6185d1cbba2360d06b0521025
    PCSF00403\tEU\tKillzone: Mercenary Botzone Soldier Training\
    \thttp://zeus.dl.playstation.net/cdn/EP9000/PCSF00243_00/gdOOmlDKYLSDmWMUyhnEqPSGhkkkdxGLjWAzDO\
    pwdJBXkmuHIguvmqUYweAlTCJu.pkg\
    \tKO5ifR1dQ+e7BlgiTDMyMQbZH2CAZKGlqTk+/7lvMHBdJujNcvPwRCV5tqak0Rgf3AAAp3gRYgAA\
    \tEP9000-PCSF00243_00-P000000000001957\t2017-10-19 05:49:33\t102400\
    \tc444fbc3958931e6700601377463c1bfa16637405e79b5a438b7186842f1ad4a
    """
  let catalogueItems = try CatalogParser.parseTSV(
    tsv,
    kind: CatalogKind(console: .PSV, fileType: .DLC)
  )
  #expect(catalogueItems.count == 2)
  #expect(catalogueItems.map(\.titleID) == ["PCSF00403", "PCSF00403"])
  #expect(
    Set(catalogueItems.map(\.name)) == [
      "Killzone Mercenary: M224-A1", "Killzone: Mercenary Botzone Soldier Training",
    ]
  )

  let root = try makeCompatibilityPatchDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let suiteName = "NPS-PCSF00403-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let settings = SettingsStore(defaults: defaults)
  try settings.setDownloadLibraryDirectory(
    root.appendingPathComponent("Library", isDirectory: true)
  )
  let catalogue = try RealmCatalogueStore(fileURL: root.appendingPathComponent("catalogue.realm"))
  try await catalogue.replaceItems(catalogueItems)
  let coordinator = try DownloadCoordinator(
    preferences: {
      let snapshot = settings.snapshot()
      return DownloadPreferences(
        downloadDirectory: snapshot.downloadLibraryDirectory,
        concurrentDownloads: snapshot.concurrentDownloads
      )
    },
    persistenceURL: root.appendingPathComponent("downloads.plist"),
    urlSessionConfiguration: .ephemeral
  )
  let dataSource = ApplicationDataSource(
    settings: settings,
    catalogue: catalogue,
    downloads: coordinator
  )
  let entries = try await dataSource.loadCatalogue()
  #expect(entries.count == 2)
  #expect(entries.allSatisfy { $0.consoleCode == "PSV" && $0.category == "DLC" })

  let table = CatalogTableViewController()
  let inspector = ItemInspectorViewController()
  _ = table.view
  _ = inspector.view
  table.show(section: .dlc)
  table.setEntries(entries.sorted { $0.title < $1.title })
  var selections: [BrowserEntry] = []
  table.onSelection = { entry in
    if let entry { selections.append(entry) }
    inspector.show(entry: entry, bookmarked: false)
  }
  #expect(table.numberOfRows(in: table.tableView) == 2)

  var selectedTitles = Set<String>()
  for row in 0..<table.numberOfRows(in: table.tableView) {
    table.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    let selected = try #require(table.selectedEntry)
    selectedTitles.insert(selected.title)
    #expect(selected.titleID == "PCSF00403")
    #expect(selected.category == "DLC")
    #expect(inspector.isPackageDownloadButtonVisible)
    #expect(!inspector.isRAPDownloadButtonVisible)
  }
  #expect(selectedTitles == Set(catalogueItems.map(\.name)))
  #expect(selections.count == 2)
}
