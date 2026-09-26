import AppKit
import NPSBrowserAppResources

@MainActor
final class DownloadActivityViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate, NSMenuDelegate
{
  var onAction: ((DownloadEntry, DownloadAction) -> Void)?
  /// Called when the number of listed downloads changes.
  var onSummaryChange: ((PaneSummary) -> Void)?
  let tableView = NSTableView()
  private let contextMenu = NSMenu()
  private let scrollView = NSScrollView()
  private let emptyTitle = NSTextField(labelWithString: "")
  private let emptyMessage = NSTextField(wrappingLabelWithString: "")
  private let emptyStack = NSStackView()
  private var entries: [DownloadEntry] = []

  override func loadView() {
    let root = DownloadActivityBackgroundView()

    configureTable()
    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    emptyTitle.stringValue = AppResources.localized("empty.downloads.title")
    emptyTitle.font = .systemFont(ofSize: 17, weight: .semibold)
    emptyTitle.alignment = .center
    emptyMessage.stringValue = AppResources.localized("empty.downloads.message")
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
    emptyStack.setAccessibilityLabel(AppResources.localized("empty.downloads.title"))

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
    updateEmptyState()
  }

  func setEntries(_ entries: [DownloadEntry]) {
    let selectedID = selectedEntry?.id
    self.entries = entries
    tableView.reloadData()
    if let selectedID, let selectedRow = entries.firstIndex(where: { $0.id == selectedID }) {
      tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
    } else {
      tableView.deselectAll(nil)
    }
    updateEmptyState()
  }

  var selectedEntry: DownloadEntry? {
    guard entries.indices.contains(tableView.selectedRow) else { return nil }
    return entries[tableView.selectedRow]
  }

  var displayedEntries: [DownloadEntry] { entries }

  var contextMenuInstalledOnTable: Bool {
    tableView.menu === contextMenu && contextMenu.delegate === self
  }

  func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard entries.indices.contains(row), let column = tableColumn?.identifier.rawValue else {
      return nil
    }
    let entry = entries[row]
    let cell = NSTableCellView()
    switch column {
    case "title": DownloadActivityCellBuilder.addTitle(for: entry, to: cell)
    case "state": DownloadActivityCellBuilder.addState(entry.stateTitle, to: cell)
    case "progress": DownloadActivityCellBuilder.addProgress(for: entry, to: cell)
    case "actions":
      DownloadActivityCellBuilder.addActions(
        entry.availableActions,
        for: entry,
        to: cell,
        titleForAction: \.title,
        target: self,
        action: #selector(rowAction(_:))
      )
    default: return nil
    }
    cell.setAccessibilityElement(true)
    let rowAccessibilityLabel =
      if entry.state == .failed, !entry.detail.isEmpty {
        String(
          format: AppResources.localized("downloads.row.accessibilityWithDetail"),
          entry.title,
          entry.stateTitle,
          entry.detail
        )
      } else {
        String(
          format: AppResources.localized("downloads.row.accessibility"),
          entry.title,
          entry.stateTitle
        )
      }
    cell.setAccessibilityLabel(rowAccessibilityLabel)
    return cell
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    guard entries.indices.contains(row), entries[row].state == .failed, !entries[row].detail.isEmpty
    else { return 54 }

    let titleColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("title"))
    let textWidth = max(80, (titleColumn?.width ?? 260) - 12)
    let detailFont = NSFont.systemFont(ofSize: 11)
    let measuredDetail = NSAttributedString(
      string: entries[row].detail,
      attributes: [.font: detailFont]
    ).boundingRect(
      with: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let titleAndSpacing: CGFloat = 18 + 2
    let verticalInsets: CGFloat = 10
    return max(54, ceil(titleAndSpacing + measuredDetail.height + verticalInsets))
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let row = tableView.clickedRow
    guard entries.indices.contains(row) else { return }
    if tableView.selectedRow != row {
      tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
    for action in entries[row].availableActions {
      let item = NSMenuItem(
        title: action.title,
        action: #selector(contextAction(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.tag = action.rawValue
      menu.addItem(item)
    }
  }

  @objc
  private func rowAction(_ sender: NSButton) {
    guard let id = sender.identifier?.rawValue, let entry = entries.first(where: { $0.id == id }),
      let action = DownloadAction(rawValue: sender.tag), entry.canPerform(action)
    else { return }
    onAction?(entry, action)
  }

  @objc
  private func contextAction(_ sender: NSMenuItem) {
    guard entries.indices.contains(tableView.selectedRow),
      let action = DownloadAction(rawValue: sender.tag)
    else { return }
    let entry = entries[tableView.selectedRow]
    guard entry.canPerform(action) else { return }
    onAction?(entry, action)
  }

  private func configureTable() {
    tableView.delegate = self
    tableView.dataSource = self
    tableView.rowHeight = 54
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.selectionHighlightStyle = .regular
    tableView.setAccessibilityLabel(AppResources.localized("downloads.accessibility.label"))
    addColumn(
      "title",
      title: AppResources.localized("downloads.column.download"),
      width: 260,
      minWidth: 140
    )
    addColumn(
      "state",
      title: AppResources.localized("downloads.column.status"),
      width: 130,
      minWidth: 90
    )
    addColumn(
      "progress",
      title: AppResources.localized("downloads.column.progress"),
      width: 145,
      minWidth: 90
    )
    addColumn(
      "actions",
      title: AppResources.localized("downloads.column.actions"),
      width: 300,
      minWidth: 210
    )
    contextMenu.delegate = self
    tableView.menu = contextMenu
  }

  private func addColumn(_ identifier: String, title: String, width: CGFloat, minWidth: CGFloat) {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
    column.title = title
    column.width = width
    column.minWidth = minWidth
    tableView.addTableColumn(column)
  }

  private func updateEmptyState() {
    let isEmpty = entries.isEmpty
    emptyStack.isHidden = !isEmpty
    scrollView.isHidden = isEmpty
    onSummaryChange?(summary)
  }

  var summary: PaneSummary {
    PaneSummary(
      title: AppResources.localized("section.downloads"),
      subtitle: CountText.string(entries.count, key: "downloads.count")
    )
  }
}
