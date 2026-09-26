import AppKit
import NPSBrowserAppResources

extension BrowserViewController {
  func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
    if item.action == #selector(toggleBookmark(_:)) { updateBookmarkToolbarItem(item) }
    return isCatalogueActionEnabled(for: item.action)
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(toggleBookmark(_:)),
      let selectedEntry = catalogueController.selectedEntry
    {
      menuItem.title = AppResources.localized(
        bookmarkedIDs.contains(selectedEntry.id) ? "action.bookmark.remove" : "action.bookmark.add"
      )
    }
    if let action = downloadAction(for: menuItem.action) {
      return canPerformSelectedDownloadAction(action)
    }
    return isCatalogueActionEnabled(for: menuItem.action)
  }
  private func downloadAction(for selector: Selector?) -> DownloadAction? {
    guard let selector else { return nil }
    switch selector {
    case #selector(pauseSelectedDownload(_:)): return .pause
    case #selector(resumeSelectedDownload(_:)): return .resume
    case #selector(restartSelectedDownload(_:)): return .restart
    case #selector(retryExtractionSelectedDownload(_:)): return .retryExtraction
    case #selector(removeSelectedDownload(_:)): return .remove
    case #selector(revealSelectedDownload(_:)): return .reveal
    default: return nil
    }
  }
  private func isCatalogueActionEnabled(for action: Selector?) -> Bool {
    guard let action else { return true }
    switch action {
    case #selector(downloadSelected(_:)):
      return section != .downloads
        && catalogueController.selectedEntry?.supportsPackageDownload == true
    case #selector(downloadUpdateSelected(_:)):
      return section != .downloads
        && catalogueController.selectedEntry?.supportsUpdateDownload == true
    case #selector(downloadRAPSelected(_:)):
      return section != .downloads && catalogueController.selectedEntry?.supportsRAPDownload == true
    case #selector(toggleBookmark(_:)):
      return section != .downloads
        && catalogueController.selectedEntry.map { !$0.isCompatibilityPack } == true
    case #selector(toggleInspectorPane(_:)): return section != .downloads
    default: return true
    }
  }

  func validateVisibleToolbarItems() {
    guard isViewLoaded, let toolbar = view.window?.toolbar else { return }
    // validateVisibleItems() skips items that are not laid out (for example
    // in the overflow menu), so refresh the bookmark label directly.
    for item in toolbar.items where item.action == #selector(toggleBookmark(_:)) {
      updateBookmarkToolbarItem(item)
    }
    toolbar.validateVisibleItems()
  }

  private func updateBookmarkToolbarItem(_ item: NSToolbarItem) {
    let isBookmarked =
      catalogueController.selectedEntry.map { bookmarkedIDs.contains($0.id) } ?? false
    let key = isBookmarked ? "action.bookmark.remove" : "action.bookmark.add"
    let label = AppResources.localized(key)
    item.label = label
    item.paletteLabel = label
    item.toolTip = label
    item.image = AppSymbols.image(named: isBookmarked ? "star.fill" : "star", description: label)
  }
}
