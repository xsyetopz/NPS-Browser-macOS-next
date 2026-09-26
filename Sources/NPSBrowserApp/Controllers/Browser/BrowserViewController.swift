import AppKit
import NPSBrowserAppResources

@MainActor
final class BrowserViewController: NSViewController, NSSearchFieldDelegate, NSToolbarItemValidation,
  NSMenuItemValidation
{
  var onError: ((String) -> Void)?
  var activeRemovalConfirmationPresenter:
    ((NSAlert, DownloadEntry, @escaping (Bool) -> Void) -> Void)?
  let dataSource: any BrowserDataSource
  let volumeNotificationSubscriptions: WorkspaceNotificationSubscriptions
  private let splitController = NSSplitViewController()
  private let contentController = BrowserContentViewController()
  private let navigationController = NavigationViewController()
  let catalogueController = CatalogTableViewController()
  let inspectorController = ItemInspectorViewController()
  let downloadsController = DownloadActivityViewController()
  private(set) var section: BrowserSection = .allItems
  /// The user's choice, kept across launches. Downloads always hides the
  /// inspector, and the split view's autosave would otherwise restore that.
  private let interfacePreferences = InterfacePreferences()
  private var isInspectorHiddenByUser: Bool {
    get { interfacePreferences.isInspectorHidden }
    set { interfacePreferences.isInspectorHidden = newValue }
  }
  private var inspectorItem: NSSplitViewItem?
  private var entries: [BrowserEntry] = []
  var bookmarkWrites = BookmarkWriteLedger()
  var bookmarkedIDs: Set<String> { bookmarkWrites.bookmarkedIDs }
  var catalogueSelectionRevision: UInt64 = 0
  var bookmarkContextRevision: UInt64 = 0
  var lastSearchText = ""
  private var reloadTask: Task<Void, Never>?
  private var pendingForcedReload = false
  var preferencesWindowController: PreferencesWindowController?
  private var downloadStartupTask: Task<Void, Never>?
  var downloadUpdatesTask: Task<Void, Never>?
  var downloadReloadGeneration: UInt64 = 0
  var latestDownloadReloadTask: Task<Void, Never>?
  var latestDownloadReloadTaskGeneration: UInt64?
  var persistedDownloadEntries: [DownloadEntry] = []
  var pendingDownloads = PendingDownloads()

  init(dataSource: any BrowserDataSource, workspaceNotificationCenter: NotificationCenter? = nil) {
    self.dataSource = dataSource
    volumeNotificationSubscriptions = WorkspaceNotificationSubscriptions(
      center: workspaceNotificationCenter ?? NSWorkspace.shared.notificationCenter
    )
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func loadView() {
    splitController.splitView.isVertical = true
    splitController.splitView.dividerStyle = .thin
    splitController.splitView.autosaveName = "NPSBrowser.MainSplitView"

    let sidebarItem = NSSplitViewItem(sidebarWithViewController: navigationController)
    sidebarItem.minimumThickness = 190
    sidebarItem.maximumThickness = 250
    let catalogueItem = NSSplitViewItem(viewController: contentController)
    catalogueItem.minimumThickness = 440
    let inspectorItem: NSSplitViewItem
    if #available(macOS 14.0, *) {
      inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorController)
    } else {
      inspectorItem = NSSplitViewItem(viewController: inspectorController)
      inspectorItem.canCollapse = true
    }
    inspectorItem.minimumThickness = 240
    inspectorItem.maximumThickness = 360
    self.inspectorItem = inspectorItem
    splitController.addSplitViewItem(sidebarItem)
    splitController.addSplitViewItem(catalogueItem)
    splitController.addSplitViewItem(inspectorItem)
    addChild(splitController)
    view = splitController.view
    contentController.show(catalogueController)

    navigationController.onSelect = { [weak self] section in self?.show(section: section) }
    catalogueController.onSummaryChange = { [weak self] summary in
      guard let self, self.section != .downloads else { return }
      self.applyWindowSummary(summary)
    }
    downloadsController.onSummaryChange = { [weak self] summary in
      guard let self, self.section == .downloads else { return }
      self.applyWindowSummary(summary)
    }
    catalogueController.onSelection = { [weak self] entry in
      guard let self else { return }
      self.inspectorController.show(
        entry: entry,
        bookmarked: entry.map { self.bookmarkedIDs.contains($0.id) } ?? false
      )
      self.validateVisibleToolbarItems()
    }
    catalogueController.onUserSelectionChange = { [weak self] _ in
      self?.catalogueSelectionRevision &+= 1
    }
    catalogueController.onDownload = { [weak self] entry in self?.enqueue(entry) }
    catalogueController.onDownloadRAP = { [weak self] entry in self?.enqueueRAP(entry) }
    catalogueController.onBookmark = { [weak self] entry in self?.toggleBookmark(for: entry) }
    inspectorController.onDownload = { [weak self] in
      guard let self, self.section != .downloads,
        let entry = self.catalogueController.selectedEntry, entry.supportsPackageDownload
      else { return }
      self.enqueue(entry)
    }
    inspectorController.onBookmark = { [weak self] in
      guard let self, self.section != .downloads, let entry = self.catalogueController.selectedEntry
      else { return }
      self.toggleBookmark(for: entry)
    }
    inspectorController.onDownloadUpdate = { [weak self] entry in self?.enqueueUpdate(entry) }
    inspectorController.onDownloadRAP = { [weak self] entry in self?.enqueueRAP(entry) }
    downloadsController.onAction = { [weak self] download, action in
      self?.perform(action, for: download)
    }

    Task { await reloadData(forceRefresh: false) }
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    applyWindowSummary(currentSummary)
    inspectorItem?.isCollapsed = section == .downloads || isInspectorHiddenByUser
  }

  var currentSummary: PaneSummary {
    section == .downloads ? downloadsController.summary : catalogueController.summary
  }

  /// The window title names the visible pane; the count goes in the subtitle
  /// (macOS 11+) or after the title on 10.15, which has no subtitle.
  private func applyWindowSummary(_ summary: PaneSummary) {
    guard let window = view.window, !summary.title.isEmpty else { return }
    if #available(macOS 11.0, *) {
      window.title = summary.title
      window.subtitle = summary.subtitle
    } else {
      window.title = String(
        format: AppResources.localized("window.title.format"),
        summary.title,
        summary.subtitle
      )
    }
  }

  @objc
  func toggleInspectorPane(_ sender: Any?) {
    guard let inspectorItem, section != .downloads else { return }
    isInspectorHiddenByUser = !inspectorItem.isCollapsed
    if view.window?.isVisible == true {
      inspectorItem.animator().isCollapsed = isInspectorHiddenByUser
    } else {
      inspectorItem.isCollapsed = isInspectorHiddenByUser
    }
  }

  var isInspectorVisible: Bool { inspectorItem?.isCollapsed == false }
  func presentStartupError(_ message: String) { showError(message) }
  private func show(section newSection: BrowserSection) {
    if section != newSection { bookmarkContextRevision &+= 1 }
    section = newSection
    validateVisibleToolbarItems()
    if newSection == .downloads {
      downloadStartupTask?.cancel()
      downloadUpdatesTask?.cancel()
      downloadUpdatesTask = nil
      startWorkspaceVolumeNotifications()
      inspectorItem?.isCollapsed = true
      applyWindowSummary(downloadsController.summary)
      // Cached rows can predate a volume change made while Downloads was
      // hidden. Withhold Reveal until the fresh snapshot confirms each file.
      persistedDownloadEntries = persistedDownloadEntries.map { entry in
        var entry = entry
        entry.completedFile = nil
        return entry
      }
      refreshDownloadEntries()
      contentController.show(downloadsController)
      downloadStartupTask = Task { [weak self] in
        guard let self else { return }
        await self.reloadDownloads()
        guard !Task.isCancelled, self.section == .downloads else { return }
        await self.startDownloadUpdates()
      }
    } else {
      stopWorkspaceVolumeNotifications()
      downloadStartupTask?.cancel()
      downloadStartupTask = nil
      downloadUpdatesTask?.cancel()
      downloadUpdatesTask = nil
      contentController.show(catalogueController)
      inspectorItem?.isCollapsed = isInspectorHiddenByUser
      catalogueController.show(section: newSection)
    }
  }

  func navigate(to newSection: BrowserSection) {
    if section == newSection {
      show(section: newSection)
    } else {
      navigationController.select(newSection)
    }
  }

  /// Reloads the catalogue. A forced reload requested while another reload runs is queued
  /// (coalesced into one) and the caller's await ends only after that queued run finishes.
  func reloadData(forceRefresh: Bool) async {
    if let reloadTask {
      if forceRefresh { pendingForcedReload = true }
      await reloadTask.value
      return
    }
    let task = Task {
      var force = forceRefresh
      while true {
        await performReload(forceRefresh: force)
        guard pendingForcedReload else { break }
        pendingForcedReload = false
        force = true
      }
      reloadTask = nil
    }
    reloadTask = task
    await task.value
  }

  private func performReload(forceRefresh: Bool) async {
    catalogueController.setLoading(true)
    defer { catalogueController.setLoading(false) }
    do {
      var loadedEntries = try await dataSource.loadCatalogue()
      if forceRefresh || !loadedEntries.contains(where: { !$0.isCompatibilityPack }) {
        loadedEntries = try await dataSource.refreshCatalogue()
      }
      async let loadedBookmarks = dataSource.loadBookmarkedIDs()
      entries = loadedEntries
      bookmarkWrites.reset(to: try await loadedBookmarks)
      let preferences = try? await dataSource.loadPreferences()
      catalogueController.setHideInvalidURLItems(preferences?.hideInvalidURLItems ?? true)
      catalogueController.setEntries(entries)
      catalogueController.setBookmarks(bookmarkedIDs)
      catalogueController.show(section: section == .downloads ? .allItems : section)
    } catch {
      let refreshError = error
      do {
        entries = try await dataSource.loadCatalogue()
        bookmarkWrites.reset(to: try await dataSource.loadBookmarkedIDs())
        catalogueController.setEntries(entries)
        catalogueController.setBookmarks(bookmarkedIDs)
        if section != .downloads { catalogueController.show(section: section) }
      } catch {
        // Keep the current view when even the fallback database read fails.
      }
      showError(refreshError.localizedDescription)
    }
  }
  func showError(_ message: String) {
    if let onError {
      onError(message)
      return
    }
    let alert = NSAlert()
    alert.messageText = AppResources.localized("error.title")
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: AppResources.localized("alert.ok"))
    if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
  }
}
