import AppKit
import NPSBrowserAppResources

extension PreferencesViewController {
  func showError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = AppResources.localized("preferences.saveError")
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: AppResources.localized("alert.ok"))
    if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
  }
}
