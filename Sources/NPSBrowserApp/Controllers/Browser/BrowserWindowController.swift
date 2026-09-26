import AppKit
import NPSBrowserAppResources

@MainActor
final class BrowserWindowController: NSWindowController, NSToolbarDelegate {
  let browserViewController: BrowserViewController
  private let searchField = NSSearchField()

  init(dataSource: any BrowserDataSource) {
    browserViewController = BrowserViewController(dataSource: dataSource)
    var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    // macOS 11+: the sidebar runs full height under a unified toolbar.
    if #available(macOS 11.0, *) { styleMask.insert(.fullSizeContentView) }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
      styleMask: styleMask,
      backing: .buffered,
      defer: false
    )
    window.title = AppResources.localized("app.name")
    if #available(macOS 11.0, *) { window.toolbarStyle = .unified }
    window.minSize = NSSize(width: 900, height: 600)
    window.center()
    window.contentViewController = browserViewController
    super.init(window: window)
    windowFrameAutosaveName = "NPSBrowser.MainWindow"

    let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
    toolbar.delegate = self
    toolbar.allowsUserCustomization = true
    toolbar.autosavesConfiguration = true
    let hadSavedConfiguration = ToolbarDisplayModeMigration.hasSavedConfiguration(
      identifier: Self.toolbarIdentifier
    )
    searchField.placeholderString = AppResources.localized("search.placeholder")
    searchField.setAccessibilityLabel(AppResources.localized("search.placeholder"))
    searchField.sendsSearchStringImmediately = true
    searchField.delegate = browserViewController
    searchField.translatesAutoresizingMaskIntoConstraints = false
    // Prefer 260 pt but shrink to 140 pt before the toolbar overflows.
    let preferredWidth = searchField.widthAnchor.constraint(equalToConstant: 260)
    preferredWidth.priority = .defaultLow
    NSLayoutConstraint.activate([
      preferredWidth, searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
      searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
      searchField.heightAnchor.constraint(equalToConstant: 28),
    ])

    window.toolbar = toolbar
    if ToolbarDisplayModeMigration.shouldApplyIconOnlyDefault(
      hasExistingSavedConfiguration: hadSavedConfiguration
    ) {
      toolbar.displayMode = .iconOnly
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    Self.defaultItemIdentifiers + [Self.downloadsIdentifier, .space]
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    Self.defaultItemIdentifiers
  }

  /// Sidebar toggle over the sidebar, item actions, then search and the
  /// inspector toggle at the trailing edge. Downloads stays in the palette:
  /// the sidebar and View menu already open it.
  static var defaultItemIdentifiers: [NSToolbarItem.Identifier] {
    var identifiers: [NSToolbarItem.Identifier] = [.toggleSidebar]
    if #available(macOS 11.0, *) { identifiers.append(.sidebarTrackingSeparator) }
    identifiers += [
      .flexibleSpace, downloadIdentifier, bookmarkIdentifier, searchIdentifier, inspectorIdentifier,
    ]
    return identifiers
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    if itemIdentifier == Self.searchIdentifier {
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.label = AppResources.localized("search.placeholder")
      item.paletteLabel = item.label
      item.toolTip = item.label
      item.view = searchField
      return item
    }

    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    switch itemIdentifier {
    case Self.bookmarkIdentifier:
      item.label = AppResources.localized("action.bookmark.add")
      item.paletteLabel = item.label
      item.toolTip = item.label
      item.image = AppSymbols.image(named: "star", description: item.label)
      item.action = #selector(BrowserViewController.toggleBookmark(_:))
    case Self.downloadIdentifier:
      item.label = AppResources.localized("action.download")
      item.paletteLabel = item.label
      item.toolTip = item.label
      item.image = AppSymbols.image(named: "arrow.down.circle", description: item.label)
      item.action = #selector(BrowserViewController.downloadSelected(_:))
    case Self.downloadsIdentifier:
      item.label = AppResources.localized("section.downloads")
      item.paletteLabel = item.label
      item.toolTip = item.label
      item.image = AppSymbols.image(named: "list.bullet.rectangle", description: item.label)
      item.action = #selector(BrowserViewController.showDownloads(_:))
    case Self.inspectorIdentifier:
      item.label = AppResources.localized("toolbar.inspector")
      item.paletteLabel = item.label
      item.toolTip = AppResources.localized("action.toggleInspector")
      item.image = AppSymbols.image(named: "sidebar.right", description: item.toolTip ?? item.label)
      item.action = #selector(BrowserViewController.toggleInspectorPane(_:))
    default: return nil
    }
    item.target = browserViewController
    item.isEnabled = true
    return item
  }

  // v2: layouts autosaved under the pre-release identifier kept a labelled,
  // centred-search arrangement; a new identifier starts from the defaults.
  static let toolbarIdentifier = NSToolbar.Identifier("NPSBrowser.MainToolbar.v2")
  private static let searchIdentifier = NSToolbarItem.Identifier("NPSBrowser.Search")
  private static let bookmarkIdentifier = NSToolbarItem.Identifier("NPSBrowser.Bookmark")
  private static let downloadIdentifier = NSToolbarItem.Identifier("NPSBrowser.Download")
  private static let downloadsIdentifier = NSToolbarItem.Identifier("NPSBrowser.Downloads")
  private static let inspectorIdentifier = NSToolbarItem.Identifier("NPSBrowser.Inspector")
}
