import AppKit
import NPSBrowserAppResources

extension PreferencesViewController {
  static func chooseDirectory(startingAt path: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = AppResources.localized("preferences.chooseDownloadLocation")
    panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url
  }
}
