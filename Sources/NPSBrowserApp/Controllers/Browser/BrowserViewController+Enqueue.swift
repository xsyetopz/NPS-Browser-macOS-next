import AppKit

extension BrowserViewController {
  func enqueue(_ entry: BrowserEntry) {
    guard section != .downloads, entry.supportsPackageDownload else { return }
    startEnqueue(
      key: PendingDownloads.packageKey(for: entry),
      placeholder: PendingDownloads.packagePlaceholder(for: entry)
    ) { [dataSource] jobID in try await dataSource.enqueue(entry, jobID: jobID) }
  }

  func enqueueUpdate(_ entry: BrowserEntry) {
    guard section != .downloads, entry.supportsUpdateDownload else { return }
    startEnqueue(
      key: PendingDownloads.updateKey(for: entry),
      placeholder: PendingDownloads.updatePlaceholder(for: entry)
    ) { [dataSource] jobID in try await dataSource.enqueueUpdate(entry, jobID: jobID) }
  }

  func enqueueRAP(_ entry: BrowserEntry) {
    guard section != .downloads, entry.supportsRAPDownload else { return }
    startEnqueue(
      key: PendingDownloads.rapKey(for: entry),
      placeholder: PendingDownloads.rapPlaceholder(for: entry)
    ) { [dataSource] jobID in try await dataSource.enqueueRAP(entry, jobID: jobID) }
  }

  private func startEnqueue(
    key: String,
    placeholder: DownloadEntry,
    submit: @escaping @MainActor (UUID) async throws -> Void
  ) {
    let jobID = UUID()
    guard pendingDownloads.add(key: key, jobID: jobID, placeholder: placeholder) else { return }
    navigate(to: .downloads)
    refreshDownloadEntries()
    Task {
      do { try await submit(jobID) } catch {
        removePendingEnqueue(key: key, jobID: jobID)
        showError(error.localizedDescription)
      }
      await reloadDownloads()
      // Normally the snapshot has already replaced the placeholder. A
      // deduplicated request keeps an existing job's ID, and a failed
      // reload has no snapshot, so neither may strand the placeholder.
      removePendingEnqueue(key: key, jobID: jobID)
    }
  }

  private func removePendingEnqueue(key: String, jobID: UUID) {
    guard pendingDownloads.remove(key: key, jobID: jobID) else { return }
    refreshDownloadEntries()
  }
  func refreshDownloadEntries() {
    pendingDownloads.resolve(against: persistedDownloadEntries)
    downloadsController.setEntries(pendingDownloads.merged(with: persistedDownloadEntries))
  }
}
