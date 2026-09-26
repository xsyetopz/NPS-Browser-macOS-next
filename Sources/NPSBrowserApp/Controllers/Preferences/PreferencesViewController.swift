import AppKit
import NPSCore

/// Settings apply immediately: controls persist on change and catalogue URLs
/// persist when editing ends, if valid.
@MainActor
final class PreferencesViewController: NSViewController {
  /// Called after a changed catalogue URL is saved, so the catalogue reloads.
  /// Calls run one at a time, in save order.
  var onSaved: (() async -> Void)?
  var onHideInvalidURLItemsChanged: ((Bool) -> Void)?
  var chooseDirectory: (String) -> URL? = {
    PreferencesViewController.chooseDirectory(startingAt: $0)
  }
  private let dataSource: any BrowserDataSource
  private let formView = PreferencesFormView()
  /// The latest accepted value; saves are queued in order behind `pendingSave`.
  private var preferences: BrowserPreferences?
  private var pendingSave: Task<Void, Never>?
  private var pendingReload: Task<Void, Never>?

  init(dataSource: any BrowserDataSource) {
    self.dataSource = dataSource
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func loadView() {
    formView.onValuesChanged = { [weak self] in self?.persistFormValues() }
    formView.onCatalogueURLCommitted = { [weak self] source, text in
      self?.commitCatalogueURL(text, for: source)
    }
    formView.onChooseDownloadDirectory = { [weak self] in self?.chooseDownloadDirectory() }
    view = formView
    reloadPreferences()
  }

  /// Shows the persisted settings again, dropping unsaved URL edits.
  func reloadPreferences() {
    Task {
      await pendingSave?.value
      await loadPreferences()
    }
  }

  /// Saves the URL still being edited, as ending the edit would.
  func commitPendingCatalogueURL() { formView.commitDisplayedCatalogueURL() }

  /// Waits for every queued save, and the catalogue reloads they started, to finish.
  func waitForPendingSaves() async {
    await pendingSave?.value
    await pendingReload?.value
  }

  private func chooseDownloadDirectory() {
    guard let url = chooseDirectory(formView.downloadDirectoryPath) else { return }
    formView.downloadDirectoryPath = url.path
    persistFormValues()
  }

  private func persistFormValues() {
    guard let preferences else { return }
    switch preferences.applying(formView.formValues) {
    case let .success(updated):
      let hideChanged = updated.hideInvalidURLItems != preferences.hideInvalidURLItems
      save(updated) { [weak self] in
        if hideChanged { self?.onHideInvalidURLItemsChanged?(updated.hideInvalidURLItems) }
      }
    case let .failure(failure):
      formView.apply(preferences)
      showError(failure.formMessage)
    }
  }

  private func commitCatalogueURL(_ text: String, for source: CatalogSource) {
    guard let preferences else { return }
    guard preferences.catalogueURLs[source]?.absoluteString != text else {
      formView.validationMessage = ""
      return
    }
    switch preferences.applyingCatalogueURL(text, for: source) {
    case let .success(updated):
      formView.validationMessage = ""
      if let url = updated.catalogueURLs[source] {
        formView.markCatalogueURLSaved(url, for: source)
      }
      save(updated) { [weak self] in self?.queueCatalogueReload() }
    case let .failure(failure): formView.validationMessage = failure.formMessage
    }
  }

  private func queueCatalogueReload() {
    guard let onSaved else { return }
    let previous = pendingReload
    pendingReload = Task {
      await previous?.value
      await onSaved()
    }
  }

  private func save(_ updated: BrowserPreferences, then completion: @escaping () -> Void) {
    preferences = updated
    let previous = pendingSave
    pendingSave = Task { [dataSource] in
      await previous?.value
      do {
        try await dataSource.savePreferences(updated)
        completion()
      } catch {
        showError(error.localizedDescription)
        await loadPreferences()
      }
    }
  }

  private func loadPreferences() async {
    do {
      let loaded = try await dataSource.loadPreferences()
      preferences = loaded
      formView.apply(loaded)
    } catch { showError(error.localizedDescription) }
  }
}
