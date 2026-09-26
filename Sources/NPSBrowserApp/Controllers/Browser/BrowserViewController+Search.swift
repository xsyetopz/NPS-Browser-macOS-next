import AppKit

extension BrowserViewController {
  func controlTextDidChange(_ notification: Notification) {
    guard let field = notification.object as? NSSearchField else { return }
    if field.stringValue != lastSearchText {
      lastSearchText = field.stringValue
      bookmarkContextRevision &+= 1
    }
    catalogueController.search(field.stringValue)
  }
}
