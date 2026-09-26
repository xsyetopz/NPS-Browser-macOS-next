import AppKit
import NPSBrowserAppResources

extension BrowserViewController {
  @objc
  func pauseSelectedDownload(_ sender: Any?) { performSelectedDownloadAction(.pause) }
  @objc
  func resumeSelectedDownload(_ sender: Any?) { performSelectedDownloadAction(.resume) }
  @objc
  func restartSelectedDownload(_ sender: Any?) { performSelectedDownloadAction(.restart) }
  @objc
  func retryExtractionSelectedDownload(_ sender: Any?) {
    performSelectedDownloadAction(.retryExtraction)
  }
  @objc
  func removeSelectedDownload(_ sender: Any?) { performSelectedDownloadAction(.remove) }
  @objc
  func revealSelectedDownload(_ sender: Any?) { performSelectedDownloadAction(.reveal) }
  func reloadDownloads() async {
    downloadReloadGeneration &+= 1
    let generation = downloadReloadGeneration
    let reloadTask = Task { [weak self] in
      guard let self else { return }
      await self.loadDownloadSnapshot(generation: generation)
    }
    latestDownloadReloadTask = reloadTask
    latestDownloadReloadTaskGeneration = generation

    await reloadTask.value
    // A superseded caller also waits for the newest request. This keeps an
    // awaited refresh from returning while a later state update is still
    // pending (for example, when the view enters Downloads and refreshes
    // immediately before a command performs its own refresh).
    while let latestGeneration = latestDownloadReloadTaskGeneration, latestGeneration != generation,
      let latestTask = latestDownloadReloadTask
    {
      await latestTask.value
      if latestDownloadReloadTaskGeneration == latestGeneration { return }
    }
  }

  private func loadDownloadSnapshot(generation: UInt64) async {
    do {
      let entries = try await dataSource.loadDownloads()
      // Mount/unmount and coordinator updates can overlap. Only the most
      // recently requested snapshot may change visible job state.
      guard generation == downloadReloadGeneration else { return }
      setDownloadEntries(entries)
    } catch {
      guard generation == downloadReloadGeneration else { return }
      showError(error.localizedDescription)
    }
  }

  func startDownloadUpdates() async {
    downloadUpdatesTask?.cancel()
    downloadUpdatesTask = nil
    let updates = await dataSource.observeDownloads()
    guard !Task.isCancelled, section == .downloads else { return }
    downloadUpdatesTask = Task { [weak self] in
      for await _ in updates {
        guard let self, self.section == .downloads else { return }
        // Stream payloads can have been buffered before a mount or
        // unmount transition. Treat them as invalidation signals and
        // reload the authoritative snapshot instead of applying them.
        await self.reloadDownloads()
      }
    }
  }

  func startWorkspaceVolumeNotifications() {
    volumeNotificationSubscriptions.start(names: [
      NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
    ]) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, self.section == .downloads else { return }
        await self.reloadDownloads()
      }
    }
  }

  func stopWorkspaceVolumeNotifications() { volumeNotificationSubscriptions.stop() }

  private func setDownloadEntries(_ persistedEntries: [DownloadEntry]) {
    persistedDownloadEntries = persistedEntries
    refreshDownloadEntries()
  }
  func canPerformSelectedDownloadAction(_ action: DownloadAction) -> Bool {
    guard section == .downloads, let entry = downloadsController.selectedEntry else { return false }
    return entry.canPerform(action)
  }

  private func performSelectedDownloadAction(_ action: DownloadAction) {
    guard canPerformSelectedDownloadAction(action), let entry = downloadsController.selectedEntry
    else { return }
    perform(action, for: entry)
  }
  func perform(_ action: DownloadAction, for download: DownloadEntry) {
    guard section == .downloads, download.canPerform(action) else { return }
    if action == .remove, download.requiresRemovalConfirmation {
      confirmActiveRemoval(of: download)
      return
    }
    run(action, for: download)
  }

  func activeRemovalConfirmationAlert(for download: DownloadEntry) -> NSAlert {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = AppResources.localized("downloads.remove.confirm.title")
    alert.informativeText = String(
      format: AppResources.localized("downloads.remove.confirm.message"),
      download.title
    )
    alert.addButton(withTitle: AppResources.localized("downloads.remove.confirm.cancel"))
    alert.addButton(withTitle: AppResources.localized("downloads.remove.confirm.action"))
    return alert
  }

  private func confirmActiveRemoval(of download: DownloadEntry) {
    let alert = activeRemovalConfirmationAlert(for: download)
    let confirm: (Bool) -> Void = { [weak self] confirmed in
      guard confirmed else { return }
      self?.run(.remove, for: download)
    }
    if let activeRemovalConfirmationPresenter {
      activeRemovalConfirmationPresenter(alert, download, confirm)
      return
    }
    guard isViewLoaded, let window = view.window else { return }
    alert.beginSheetModal(for: window) { response in confirm(response == .alertSecondButtonReturn) }
  }

  private func run(_ action: DownloadAction, for download: DownloadEntry) {
    Task {
      do {
        if action == .reveal {
          let file = try await dataSource.completedFileURL(for: download.id)
          NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
          try await dataSource.controlDownload(download.id, action: action)
        }
        await reloadDownloads()
      } catch { showError(error.localizedDescription) }
    }
  }
}
