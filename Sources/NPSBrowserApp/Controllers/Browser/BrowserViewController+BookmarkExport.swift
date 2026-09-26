import AppKit
import NPSBrowserAppResources

extension BrowserViewController {
  @objc
  func exportBookmarks(_ sender: Any?) {
    Task {
      do {
        // Export all persisted bookmark records, including bookmarks whose
        // catalogue item is no longer present in the current feed.
        let bookmarks = try await dataSource.loadBookmarksForExport()
        guard !bookmarks.isEmpty else {
          showError(AppResources.localized("bookmarks.export.empty"))
          return
        }
        let panel = NSSavePanel()
        let fileExtension = "csv"
        panel.nameFieldStringValue =
          AppResources.localized("bookmarks.export.filename") + "." + fileExtension
        panel.allowedFileTypes = [fileExtension]
        panel.canCreateDirectories = true
        let complete: (NSApplication.ModalResponse) -> Void = { [self] response in
          guard response == .OK, let url = panel.url else { return }
          do { try BookmarkExportFile.write(bookmarks, to: url) } catch {
            showError(error.localizedDescription)
          }
        }
        if let window = view.window {
          panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
          complete(panel.runModal())
        }
      } catch { showError(error.localizedDescription) }
    }
  }
}
