import AppKit
import NPSBrowserAppResources

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
  static let frameAutosaveName = "NPSBrowser.SettingsWindow"
  let preferencesViewController: PreferencesViewController

  init(
    dataSource: any BrowserDataSource,
    onSaved: @escaping () async -> Void,
    onHideInvalidURLItemsChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    let viewController = PreferencesViewController(dataSource: dataSource)
    viewController.onSaved = onSaved
    viewController.onHideInvalidURLItemsChanged = onHideInvalidURLItemsChanged
    preferencesViewController = viewController
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    // macOS 13+ names this window Settings, matching the renamed app menu item.
    if #available(macOS 13.0, *) {
      window.title = AppResources.localized("settings.title")
    } else {
      window.title = AppResources.localized("preferences.title")
    }
    window.isReleasedWhenClosed = false
    window.contentViewController = viewController
    // Whole points: AppKit rounds a fractional content size, which translated labels produce.
    let fitting = viewController.view.fittingSize
    window.setContentSize(
      NSSize(width: fitting.width.rounded(.up), height: fitting.height.rounded(.up))
    )
    window.center()
    super.init(window: window)
    window.delegate = self
    windowFrameAutosaveName = Self.frameAutosaveName
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Closing keeps a valid URL that is still being edited.
  func windowWillClose(_ notification: Notification) {
    preferencesViewController.commitPendingCatalogueURL()
  }
}
