import AppKit
import Testing
@testable import NPSBrowserApp

@MainActor
@Test(.sourceEnglish)
func editMenuSendsStandardResponderChainActions() {
  // Arrange: NSApplication.shared creates the app (and sets NSApp) regardless
  // of which tests ran first.
  let application = NSApplication.shared
  let target = BrowserViewController(dataSource: EmptyBrowserDataSource())
  let previousMenu = application.mainMenu
  defer { application.mainMenu = previousMenu }
  _ = target.view

  // Act
  AppDelegate().buildMainMenu(target: target)

  // Assert
  let editActions = application.mainMenu?.items.compactMap(\.submenu).first { menu in
    menu.items.contains { $0.keyEquivalent == "x" }
  }?.items.compactMap(\.action).map(NSStringFromSelector)
  #expect(editActions == ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:"])
}
