import AppKit

extension BrowserViewController {
  @objc
  func showPreferences(_ sender: Any?) {
    let controller: PreferencesWindowController
    if let existing = preferencesWindowController {
      controller = existing
      if existing.window?.isVisible != true {
        existing.preferencesViewController.reloadPreferences()
      }
    } else {
      controller = PreferencesWindowController(
        dataSource: dataSource,
        onSaved: { [weak self] in await self?.reloadData(forceRefresh: true) },
        onHideInvalidURLItemsChanged: { [weak self] hide in
          self?.catalogueController.setHideInvalidURLItems(hide)
        }
      )
      preferencesWindowController = controller
    }
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
  }
}
