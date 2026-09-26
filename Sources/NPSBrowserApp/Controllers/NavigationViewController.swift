import AppKit
import NPSBrowserAppResources

@MainActor
final class NavigationViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  enum Row: Equatable {
    case heading(String)
    case section(BrowserSection)
  }

  var onSelect: ((BrowserSection) -> Void)?
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let rows: [Row] = [
    .heading("section.library"), .section(.allItems), .section(.ps3), .section(.psVita),
    .section(.psm), .section(.psp), .section(.psx), .heading("section.category"), .section(.games),
    .section(.updates), .section(.dlc), .section(.themes), .section(.avatars),
    .section(.compatPacks), .section(.compatPatches), .heading("section.activity"),
    .section(.bookmarks), .section(.downloads),
  ]

  override func loadView() {
    // No background: the sidebar split item supplies the system sidebar material.
    let root = NSView()

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("navigation"))
    column.title = ""
    column.resizingMask = .autoresizingMask
    tableView.addTableColumn(column)
    // The single column tracks the sidebar width so selections keep the
    // source list's inset on both sides.
    tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
    tableView.headerView = nil
    tableView.delegate = self
    tableView.dataSource = self
    if #available(macOS 11.0, *) { tableView.style = .sourceList }
    tableView.selectionHighlightStyle = .sourceList
    // Follows System Settings > Appearance > Sidebar icon size.
    tableView.rowSizeStyle = .default
    tableView.backgroundColor = .clear
    tableView.setAccessibilityLabel(AppResources.localized("navigation.accessibility.label"))

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = false
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(scrollView)

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    view = root
    tableView.reloadData()
    select(.allItems)
  }

  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
    if case .heading = rows[row] { return true }
    return false
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    if case .section = rows[row] { return true }
    return false
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    switch rows[row] {
    case .heading(let titleKey): NavigationCellBuilder.headingCell(titleKey: titleKey)
    case .section(let section): NavigationCellBuilder.sectionCell(for: section)
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    guard rows.indices.contains(row), case .section(let section) = rows[row] else { return }
    onSelect?(section)
  }

  func select(_ section: BrowserSection) {
    guard let row = rows.firstIndex(of: .section(section)) else { return }
    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    tableView.scrollRowToVisible(row)
  }
}
