import AppKit
import NPSBrowserAppResources

extension BrowserViewController {
  @objc
  func showHelp(_ sender: Any?) {
    let alert = NSAlert()
    alert.messageText = AppResources.localized("menu.helpItem")
    alert.informativeText = AppResources.localized("help.message")
    alert.alertStyle = .informational
    alert.addButton(withTitle: AppResources.localized("alert.ok"))
    if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
  }
}
