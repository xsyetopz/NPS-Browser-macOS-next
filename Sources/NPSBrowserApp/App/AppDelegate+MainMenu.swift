import AppKit
import NPSBrowserAppResources

extension AppDelegate {
  func buildMainMenu(target: BrowserViewController) {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu(title: AppResources.localized("app.name"))
    appMenu.addItem(
      withTitle: AppResources.localized("menu.about"),
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    appMenu.addItem(.separator())
    let preferencesItem = appMenu.addItem(
      withTitle: AppResources.localized("menu.preferences"),
      action: #selector(BrowserViewController.showPreferences(_:)),
      keyEquivalent: ","
    )
    preferencesItem.target = target
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: AppResources.localized("menu.hide"),
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    appMenu.addItem(
      withTitle: AppResources.localized("menu.quit"),
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    appMenuItem.submenu = appMenu

    let fileItem = NSMenuItem()
    mainMenu.addItem(fileItem)
    let fileMenu = NSMenu(title: AppResources.localized("menu.file"))
    let reloadItem = fileMenu.addItem(
      withTitle: AppResources.localized("action.reload"),
      action: #selector(BrowserViewController.reloadCatalogue(_:)),
      keyEquivalent: "r"
    )
    reloadItem.target = target
    fileMenu.addItem(.separator())
    let downloadItem = fileMenu.addItem(
      withTitle: AppResources.localized("action.download"),
      action: #selector(BrowserViewController.downloadSelected(_:)),
      keyEquivalent: ""
    )
    downloadItem.target = target
    let bookmarkItem = fileMenu.addItem(
      withTitle: AppResources.localized("action.bookmark.add"),
      action: #selector(BrowserViewController.toggleBookmark(_:)),
      keyEquivalent: ""
    )
    bookmarkItem.target = target
    let updateItem = fileMenu.addItem(
      withTitle: AppResources.localized("action.downloadUpdate"),
      action: #selector(BrowserViewController.downloadUpdateSelected(_:)),
      keyEquivalent: ""
    )
    updateItem.target = target
    let rapItem = fileMenu.addItem(
      withTitle: AppResources.localized("action.downloadRAP"),
      action: #selector(BrowserViewController.downloadRAPSelected(_:)),
      keyEquivalent: ""
    )
    rapItem.target = target
    let exportItem = fileMenu.addItem(
      withTitle: AppResources.localized("action.export"),
      action: #selector(BrowserViewController.exportBookmarks(_:)),
      keyEquivalent: ""
    )
    exportItem.target = target
    fileMenu.addItem(.separator())
    let downloadActionsItem = NSMenuItem(
      title: AppResources.localized("section.downloads"),
      action: nil,
      keyEquivalent: ""
    )
    let downloadActionsMenu = NSMenu(title: downloadActionsItem.title)
    for (key, selector) in [
      ("action.pause", #selector(BrowserViewController.pauseSelectedDownload(_:))),
      ("action.resume", #selector(BrowserViewController.resumeSelectedDownload(_:))),
      ("action.restart", #selector(BrowserViewController.restartSelectedDownload(_:))),
      (
        "action.retryExtraction",
        #selector(BrowserViewController.retryExtractionSelectedDownload(_:))
      ), ("action.remove", #selector(BrowserViewController.removeSelectedDownload(_:))),
      ("action.reveal", #selector(BrowserViewController.revealSelectedDownload(_:))),
    ] {
      let item = downloadActionsMenu.addItem(
        withTitle: AppResources.localized(key),
        action: selector,
        keyEquivalent: ""
      )
      item.target = target
    }
    downloadActionsItem.submenu = downloadActionsMenu
    fileMenu.addItem(downloadActionsItem)
    fileItem.submenu = fileMenu

    let editItem = NSMenuItem()
    mainMenu.addItem(editItem)
    let editMenu = NSMenu(title: AppResources.localized("menu.edit"))
    editMenu.addItem(
      withTitle: AppResources.localized("menu.undo"),
      action: NSSelectorFromString("undo:"),
      keyEquivalent: "z"
    )
    editMenu.addItem(
      withTitle: AppResources.localized("menu.redo"),
      action: NSSelectorFromString("redo:"),
      keyEquivalent: "z"
    ).keyEquivalentModifierMask = .shift
    editMenu.addItem(.separator())
    editMenu.addItem(
      withTitle: AppResources.localized("menu.cut"),
      action: #selector(NSText.cut(_:)),
      keyEquivalent: "x"
    )
    editMenu.addItem(
      withTitle: AppResources.localized("menu.copy"),
      action: #selector(NSText.copy(_:)),
      keyEquivalent: "c"
    )
    editMenu.addItem(
      withTitle: AppResources.localized("menu.paste"),
      action: #selector(NSText.paste(_:)),
      keyEquivalent: "v"
    )
    editMenu.addItem(
      withTitle: AppResources.localized("menu.selectAll"),
      action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a"
    )
    editItem.submenu = editMenu

    let viewItem = NSMenuItem()
    mainMenu.addItem(viewItem)
    let viewMenu = NSMenu(title: AppResources.localized("menu.view"))
    // Nil target: NSSplitViewController handles toggleSidebar: in the responder chain.
    let sidebarItem = viewMenu.addItem(
      withTitle: AppResources.localized("menu.showSidebar"),
      action: #selector(NSSplitViewController.toggleSidebar(_:)),
      keyEquivalent: "s"
    )
    sidebarItem.keyEquivalentModifierMask = [.control, .command]
    let inspectorItem = viewMenu.addItem(
      withTitle: AppResources.localized("action.toggleInspector"),
      action: #selector(BrowserViewController.toggleInspectorPane(_:)),
      keyEquivalent: "i"
    )
    inspectorItem.keyEquivalentModifierMask = [.option, .command]
    inspectorItem.target = target
    viewMenu.addItem(.separator())
    let downloadsItem = viewMenu.addItem(
      withTitle: AppResources.localized("section.downloads"),
      action: #selector(BrowserViewController.showDownloads(_:)),
      keyEquivalent: "4"
    )
    downloadsItem.target = target
    let allItemsItem = viewMenu.addItem(
      withTitle: AppResources.localized("section.all"),
      action: #selector(BrowserViewController.showAllItems(_:)),
      keyEquivalent: "1"
    )
    allItemsItem.target = target
    viewItem.submenu = viewMenu

    let helpItem = NSMenuItem()
    mainMenu.addItem(helpItem)
    let helpMenu = NSMenu(title: AppResources.localized("menu.help"))
    let helpCommand = helpMenu.addItem(
      withTitle: AppResources.localized("menu.helpItem"),
      action: #selector(BrowserViewController.showHelp(_:)),
      keyEquivalent: "?"
    )
    helpCommand.target = target
    helpItem.submenu = helpMenu

    NSApp.mainMenu = mainMenu
  }
}
