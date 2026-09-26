import AppKit
import NPSBrowserAppResources

@MainActor
final class CatalogTableViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate, NSMenuDelegate
{
  var onSelection: ((BrowserEntry?) -> Void)?
  var onUserSelectionChange: ((BrowserEntry?) -> Void)?
  var onDownload: ((BrowserEntry) -> Void)?
  var onDownloadRAP: ((BrowserEntry) -> Void)?
  var onBookmark: ((BrowserEntry) -> Void)?
  /// Called whenever the section, the visible count, or the loading state changes.
  var onSummaryChange: ((PaneSummary) -> Void)?
  private(set) var summary = PaneSummary(title: "", subtitle: "")

  let tableView = NSTableView()
  private let contextMenu = NSMenu()
  private let scrollView = NSScrollView()
  private let emptyTitle = NSTextField(labelWithString: "")
  private let emptyMessage = NSTextField(wrappingLabelWithString: "")
  private let emptyStack = NSStackView()
  private var allEntries: [BrowserEntry] = []
  private var visibleEntries: [BrowserEntry] = []
  private var bookmarkedIDs: Set<String> = []
  private var hideInvalidURLItems = true
  private var query = ""
  private var section: BrowserSection = .allItems
  private var isLoading = false
  private var isApplyingFilter = false
  private var programmaticSelectionDepth = 0

  override func loadView() {
    let root = NSView()
    root.translatesAutoresizingMaskIntoConstraints = false

    configureTable()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    emptyTitle.font = .systemFont(ofSize: 17, weight: .semibold)
    emptyTitle.textColor = .labelColor
    emptyTitle.alignment = .center
    emptyMessage.font = .systemFont(ofSize: 13)
    emptyMessage.textColor = .secondaryLabelColor
    emptyMessage.alignment = .center
    emptyMessage.maximumNumberOfLines = 3
    emptyMessage.preferredMaxLayoutWidth = 300
    emptyStack.orientation = .vertical
    emptyStack.alignment = .centerX
    emptyStack.spacing = 7
    emptyStack.addArrangedSubview(emptyTitle)
    emptyStack.addArrangedSubview(emptyMessage)
    emptyStack.translatesAutoresizingMaskIntoConstraints = false
    emptyStack.setAccessibilityElement(true)
    emptyStack.setAccessibilityRole(.group)
    emptyStack.setAccessibilityLabel(AppResources.localized("catalog.accessibility.status"))

    root.addSubview(scrollView)
    root.addSubview(emptyStack)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      emptyStack.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
      emptyStack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
      emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 28),
      emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
    ])
    view = root
    applyFilter()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    fitTitleColumn()
  }

  /// Title takes whatever width the other columns leave, so all columns stay
  /// visible at any pane width without horizontal scrolling. When the pane is
  /// too narrow for that, the other columns give up width down to their minimums.
  private func fitTitleColumn() {
    let available = scrollView.contentView.bounds.width
    guard available > 0, let titleColumn = tableView.tableColumns.first else { return }
    let others = Array(tableView.tableColumns.dropFirst())
    let spacing = tableView.intercellSpacing.width * CGFloat(tableView.numberOfColumns)
    let otherWidth = others.reduce(0) { $0 + $1.width }
    let shortfall = titleColumn.minWidth + otherWidth + spacing - available
    if shortfall > 0 {
      let slack = others.map { max(0, $0.width - $0.minWidth) }
      let totalSlack = slack.reduce(0, +)
      if totalSlack > 0 {
        let ratio = min(1, shortfall / totalSlack)
        for (column, give) in zip(others, slack) {
          column.width = (column.width - give * ratio).rounded(.down)
        }
      }
    }
    let remaining = available - others.reduce(0) { $0 + $1.width } - spacing
    let width = max(titleColumn.minWidth, remaining.rounded(.down))
    if abs(titleColumn.width - width) >= 1 { titleColumn.width = width }
  }

  func setEntries(_ entries: [BrowserEntry]) {
    allEntries = entries
    applyFilter()
  }

  func setBookmarks(_ ids: Set<String>) {
    bookmarkedIDs = ids
    applyFilter()
  }

  func setHideInvalidURLItems(_ hide: Bool) {
    hideInvalidURLItems = hide
    applyFilter()
  }

  func setLoading(_ loading: Bool) {
    isLoading = loading
    publishSummary()
  }

  func show(section newSection: BrowserSection) {
    section = newSection
    applyFilter()
  }

  func search(_ value: String) {
    query = value.trimmingCharacters(in: .whitespacesAndNewlines)
    applyFilter()
  }

  var selectedEntry: BrowserEntry? {
    guard visibleEntries.indices.contains(tableView.selectedRow) else { return nil }
    return visibleEntries[tableView.selectedRow]
  }

  @discardableResult
  func selectEntry(withID id: String) -> Bool {
    guard let row = visibleEntries.firstIndex(where: { $0.id == id }) else { return false }
    programmaticSelectionDepth += 1
    defer { programmaticSelectionDepth -= 1 }
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    return selectedEntry?.id == id
  }

  var contextMenuInstalledOnTable: Bool {
    tableView.menu === contextMenu && contextMenu.delegate === self
  }

  func numberOfRows(in tableView: NSTableView) -> Int { visibleEntries.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard visibleEntries.indices.contains(row), let identifier = tableColumn?.identifier.rawValue
    else { return nil }
    let entry = visibleEntries[row]
    let value: String
    switch identifier {
    case "title": value = entry.title
    case "console": value = entry.console
    case "titleID": value = entry.titleID
    case "region": value = entry.region
    default: value = ""
    }
    return CatalogTableCellBuilder.cell(identifier: identifier, value: value)
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let entry = selectedEntry
    onSelection?(entry)
    if !isApplyingFilter && programmaticSelectionDepth == 0 { onUserSelectionChange?(entry) }
  }

  func tableView(
    _ tableView: NSTableView,
    sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
  ) { applyFilter() }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let row = tableView.clickedRow
    guard visibleEntries.indices.contains(row) else { return }
    if tableView.selectedRow != row {
      tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
    configureContextMenu(menu, for: visibleEntries[row])
  }

  func configureContextMenu(_ menu: NSMenu, for entry: BrowserEntry) {
    menu.removeAllItems()
    if entry.supportsPackageDownload {
      let downloadItem = menu.addItem(
        withTitle: AppResources.localized("action.download"),
        action: #selector(contextDownload(_:)),
        keyEquivalent: ""
      )
      downloadItem.target = self
    }
    if entry.supportsRAPDownload {
      let rapItem = menu.addItem(
        withTitle: AppResources.localized("action.downloadRAP"),
        action: #selector(contextDownloadRAP(_:)),
        keyEquivalent: ""
      )
      rapItem.target = self
    }
    if !entry.isCompatibilityPack {
      let bookmarkTitle = AppResources.localized(
        bookmarkedIDs.contains(entry.id) ? "action.bookmark.remove" : "action.bookmark.add"
      )
      let bookmarkItem = menu.addItem(
        withTitle: bookmarkTitle,
        action: #selector(contextBookmark(_:)),
        keyEquivalent: ""
      )
      bookmarkItem.target = self
    }
  }

  @objc
  private func contextDownload(_ sender: Any?) {
    guard let selectedEntry, selectedEntry.supportsPackageDownload else { return }
    onDownload?(selectedEntry)
  }

  @objc
  func contextDownloadRAP(_ sender: Any?) {
    guard let selectedEntry, selectedEntry.supportsRAPDownload else { return }
    onDownloadRAP?(selectedEntry)
  }

  @objc
  private func contextBookmark(_ sender: Any?) {
    if let selectedEntry { onBookmark?(selectedEntry) }
  }

  private func configureTable() {
    tableView.delegate = self
    tableView.dataSource = self
    tableView.allowsMultipleSelection = false
    tableView.allowsEmptySelection = true
    tableView.usesAlternatingRowBackgroundColors = true
    if #available(macOS 11.0, *) { tableView.style = .fullWidth }
    tableView.rowHeight = 24
    tableView.selectionHighlightStyle = .regular
    // fitTitleColumn() sizes Title on each layout pass instead.
    tableView.columnAutoresizingStyle = .noColumnAutoresizing
    tableView.setAccessibilityLabel(AppResources.localized("catalog.accessibility.items"))

    addColumn("title", title: AppResources.localized("table.title"), width: 320, minWidth: 160)
    addColumn("console", title: AppResources.localized("table.console"), width: 110, minWidth: 80)
    addColumn("titleID", title: AppResources.localized("table.titleID"), width: 100, minWidth: 90)
    addColumn("region", title: AppResources.localized("table.region"), width: 60, minWidth: 50)

    contextMenu.delegate = self
    tableView.menu = contextMenu
  }

  private func addColumn(_ identifier: String, title: String, width: CGFloat, minWidth: CGFloat) {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
    column.title = title
    column.width = width
    column.minWidth = minWidth
    column.sortDescriptorPrototype = NSSortDescriptor(key: identifier, ascending: true)
    tableView.addTableColumn(column)
  }

  private func applyFilter() {
    isApplyingFilter = true
    defer { isApplyingFilter = false }
    let selectedID = selectedEntry?.id
    visibleEntries = CatalogFilter.matching(
      allEntries,
      section: section,
      bookmarkedIDs: bookmarkedIDs,
      query: query,
      hideInvalidURLItems: hideInvalidURLItems
    )
    if let descriptor = tableView.sortDescriptors.first {
      visibleEntries = CatalogSort.sorted(
        visibleEntries,
        key: descriptor.key,
        ascending: descriptor.ascending
      )
    }
    publishSummary()
    let emptyState = CatalogEmptyState.forFilter(section: section, query: query)
    emptyTitle.stringValue = AppResources.localized(emptyState.titleKey)
    emptyMessage.stringValue = AppResources.localized(emptyState.messageKey)
    let isEmpty = visibleEntries.isEmpty
    emptyStack.isHidden = !isEmpty
    scrollView.isHidden = isEmpty
    tableView.reloadData()
    if let selectedID, let selectedRow = visibleEntries.firstIndex(where: { $0.id == selectedID }) {
      tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
    } else {
      tableView.deselectAll(nil)
      onSelection?(nil)
    }
  }

  private func publishSummary() {
    let subtitle =
      isLoading
      ? AppResources.localized("status.loading")
      : CountText.string(visibleEntries.count, key: "status.items")
    summary = PaneSummary(title: AppResources.localized(section.titleKey), subtitle: subtitle)
    onSummaryChange?(summary)
  }
}
