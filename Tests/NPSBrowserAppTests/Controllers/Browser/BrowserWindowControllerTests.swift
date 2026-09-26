import AppKit
import Foundation
import NPSBrowserAppResources
import Testing
@testable import NPSBrowserApp

@Suite(.serialized, .sourceEnglish)
@MainActor
struct BrowserWindowControllerTests {
  @Test
  func firstLaunchUsesIconOnlyWhileRetainingAccessibleToolbarControls() throws {
    let defaults = UserDefaults.standard
    let migrationKey = ToolbarDisplayModeMigration.migrationKey
    let configurationKey =
      ToolbarDisplayModeMigration.configurationKeyPrefix + "NPSBrowser.MainToolbar.v2"
    let previousMigrationValue = defaults.object(forKey: migrationKey)
    let previousConfigurationValue = defaults.object(forKey: configurationKey)
    defaults.removeObject(forKey: migrationKey)
    defaults.removeObject(forKey: configurationKey)
    let controller = BrowserWindowController(dataSource: EmptyBrowserDataSource())
    let window = try #require(controller.window)
    let toolbar = try #require(window.toolbar)
    defer {
      window.close()
      if let previousMigrationValue {
        defaults.set(previousMigrationValue, forKey: migrationKey)
      } else {
        defaults.removeObject(forKey: migrationKey)
      }
      if let previousConfigurationValue {
        defaults.set(previousConfigurationValue, forKey: configurationKey)
      } else {
        defaults.removeObject(forKey: configurationKey)
      }
    }

    #expect(toolbar.displayMode == .iconOnly)
    #expect(toolbar.identifier == NSToolbar.Identifier("NPSBrowser.MainToolbar.v2"))
    #expect(toolbar.allowsUserCustomization)
    #expect(toolbar.autosavesConfiguration)
    let defaultIDs = controller.toolbarDefaultItemIdentifiers(toolbar).map(\.rawValue)
    #expect(defaultIDs.first == NSToolbarItem.Identifier.toggleSidebar.rawValue)
    if #available(macOS 11.0, *) {
      #expect(
        defaultIDs.dropFirst().first == NSToolbarItem.Identifier.sidebarTrackingSeparator.rawValue
      )
    }
    #expect(Array(defaultIDs.suffix(2)) == ["NPSBrowser.Search", "NPSBrowser.Inspector"])
    #expect(!defaultIDs.contains("NPSBrowser.Downloads"))
    #expect(
      controller.toolbarAllowedItemIdentifiers(toolbar).map(\.rawValue).contains(
        "NPSBrowser.Downloads"
      )
    )

    for rawIdentifier in ["NPSBrowser.Bookmark", "NPSBrowser.Download"] {
      let item = try #require(toolbar.items.first { $0.itemIdentifier.rawValue == rawIdentifier })
      #expect(!item.label.isEmpty)
      #expect(item.toolTip == item.label)
      #expect(item.image?.accessibilityDescription == item.label)
    }

    let inspectorItem = try #require(
      toolbar.items.first { $0.itemIdentifier.rawValue == "NPSBrowser.Inspector" }
    )
    #expect(inspectorItem.label == AppResources.localized("toolbar.inspector"))
    #expect(inspectorItem.toolTip == AppResources.localized("action.toggleInspector"))
    #expect(inspectorItem.image?.accessibilityDescription == inspectorItem.toolTip)

    let searchItem = try #require(
      toolbar.items.first { $0.itemIdentifier.rawValue == "NPSBrowser.Search" }
    )
    let searchField = try #require(searchItem.view as? NSSearchField)
    let searchPrompt = AppResources.localized("search.placeholder")
    #expect(searchItem.toolTip == searchPrompt)
    #expect(searchField.placeholderString == searchPrompt)
    #expect(searchField.accessibilityLabel() == searchPrompt)

    if let sidebarItem = toolbar.items.first(where: { $0.itemIdentifier == .toggleSidebar }) {
      #expect(!sidebarItem.label.isEmpty)
    }
  }

  @Test
  func bookmarkToolbarLabelAndAccessibilityFollowTheSelectedBookmarkState() {
    let windowController = BrowserWindowController(dataSource: EmptyBrowserDataSource())
    let window = windowController.window!
    let controller = windowController.browserViewController
    _ = controller.view
    let toolbar = window.toolbar!
    let item = toolbar.items.first { $0.itemIdentifier.rawValue == "NPSBrowser.Bookmark" }!
    let entry = BrowserEntry(
      id: "toolbar-bookmark-test",
      title: "Toolbar Bookmark Test",
      titleID: "NPUG10003",
      console: "PlayStation Mobile",
      consoleCode: "PSM",
      category: "Game",
      region: "US",
      fileSize: nil,
      packageURL: URL(string: "https://example.test/bookmark.pkg"),
      sha256: nil,
      contentID: nil
    )
    controller.catalogueController.setEntries([entry])
    controller.catalogueController.tableView.selectRowIndexes(
      IndexSet(integer: 0),
      byExtendingSelection: false
    )

    #expect(controller.validateToolbarItem(item))
    #expect(item.label == AppResources.localized("action.bookmark.add"))
    #expect(item.toolTip == AppResources.localized("action.bookmark.add"))
    #expect(item.image?.accessibilityDescription == AppResources.localized("action.bookmark.add"))

    controller.toggleBookmark(nil)
    #expect(item.label == AppResources.localized("action.bookmark.remove"))
    #expect(item.toolTip == AppResources.localized("action.bookmark.remove"))
    #expect(
      item.image?.accessibilityDescription == AppResources.localized("action.bookmark.remove")
    )

    controller.toggleBookmark(nil)
    #expect(item.label == AppResources.localized("action.bookmark.add"))
    #expect(item.toolTip == AppResources.localized("action.bookmark.add"))
    window.close()
  }

  @Test
  func capturesSyntheticBrowserWindowWithIconOnlyToolbar() async throws {
    let configurationKey =
      ToolbarDisplayModeMigration.configurationKeyPrefix + "NPSBrowser.MainToolbar.v2"
    let previousConfigurationValue = UserDefaults.standard.object(forKey: configurationKey)
    UserDefaults.standard.removeObject(forKey: configurationKey)
    let previousMigrationValue = UserDefaults.standard.object(
      forKey: ToolbarDisplayModeMigration.migrationKey
    )
    UserDefaults.standard.removeObject(forKey: ToolbarDisplayModeMigration.migrationKey)
    let controller = BrowserWindowController(dataSource: EmptyBrowserDataSource())
    let window = try #require(controller.window)
    defer {
      window.close()
      if let previousMigrationValue {
        UserDefaults.standard.set(
          previousMigrationValue,
          forKey: ToolbarDisplayModeMigration.migrationKey
        )
      } else {
        UserDefaults.standard.removeObject(forKey: ToolbarDisplayModeMigration.migrationKey)
      }
      if let previousConfigurationValue {
        UserDefaults.standard.set(previousConfigurationValue, forKey: configurationKey)
      } else {
        UserDefaults.standard.removeObject(forKey: configurationKey)
      }
    }

    let toolbar = try #require(window.toolbar)
    if ToolbarDisplayModeMigration.shouldApplyIconOnlyDefault() { toolbar.displayMode = .iconOnly }
    window.setFrame(NSRect(x: 100, y: 100, width: 1180, height: 760), display: true)
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    try await Task.sleep(nanoseconds: 200_000_000)
    window.displayIfNeeded()

    let searchItem = try #require(
      window.toolbar?.items.first { $0.itemIdentifier.rawValue == "NPSBrowser.Search" }
    )
    let searchField = try #require(searchItem.view as? NSSearchField)
    #expect(searchField.frame.width >= 240)

    let frameView = try #require(window.contentView?.superview)
    let bitmap = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
    frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let captureURL = URL(fileURLWithPath: "/tmp/nps-browser-toolbar-window.png")
    try png.write(to: captureURL, options: .atomic)
    let scale = window.backingScaleFactor
    #expect(bitmap.pixelsWide == Int((window.frame.width * scale).rounded()))
    #expect(bitmap.pixelsHigh == Int((window.frame.height * scale).rounded()))
    #expect(bitmap.pixelsWide >= 1180)
    #expect(bitmap.pixelsHigh >= 760)
    let samples = stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 16)).flatMap
    { y in
      stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 16)).map { x in
        bitmap.colorAt(x: x, y: y)
      }
    }
    #expect(Set(samples.compactMap { $0?.description }).count > 1)
    #expect(FileManager.default.fileExists(atPath: captureURL.path))
  }
}
