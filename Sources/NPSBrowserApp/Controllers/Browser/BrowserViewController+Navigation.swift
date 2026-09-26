import AppKit

extension BrowserViewController {
  @objc
  func reloadCatalogue(_ sender: Any?) { Task { await reloadData(forceRefresh: true) } }

  @objc
  func downloadSelected(_ sender: Any?) {
    guard section != .downloads, let entry = catalogueController.selectedEntry,
      entry.supportsPackageDownload
    else { return }
    enqueue(entry)
  }

  @objc
  func downloadUpdateSelected(_ sender: Any?) {
    guard section != .downloads, let entry = catalogueController.selectedEntry,
      entry.supportsUpdateDownload
    else { return }
    enqueueUpdate(entry)
  }

  @objc
  func downloadRAPSelected(_ sender: Any?) {
    guard section != .downloads, let entry = catalogueController.selectedEntry,
      entry.supportsRAPDownload
    else { return }
    enqueueRAP(entry)
  }

  @objc
  func showDownloads(_ sender: Any?) { navigate(to: .downloads) }

  @objc
  func showAllItems(_ sender: Any?) { navigate(to: .allItems) }
}
