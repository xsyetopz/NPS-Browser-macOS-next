import AppKit
import Foundation
import Testing
@testable import NPSBrowserApp

@Suite(.serialized, .sourceEnglish)
@MainActor
struct ToolbarDisplayModeMigrationTests {
  @Test
  func iconOnlyMigrationPreservesCustomizedItemsAndLaterDisplayChoice() throws {
    _ = NSApplication.shared
    let defaultsName = "NPSBrowserToolbarMigration-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }

    let toolbar = NSToolbar(identifier: "NPSBrowser.ToolbarMigrationTest.\(UUID().uuidString)")
    let delegate = ToolbarMigrationTestDelegate()
    toolbar.delegate = delegate
    toolbar.allowsUserCustomization = true
    toolbar.insertItem(withItemIdentifier: delegate.firstIdentifier, at: 0)
    toolbar.insertItem(withItemIdentifier: delegate.secondIdentifier, at: 1)
    toolbar.displayMode = .iconAndLabel
    let savedItems = toolbar.items.map(\.itemIdentifier)

    if ToolbarDisplayModeMigration.shouldApplyIconOnlyDefault(defaults: defaults) {
      toolbar.displayMode = .iconOnly
    }
    #expect(toolbar.displayMode == .iconOnly)
    #expect(toolbar.items.map(\.itemIdentifier) == savedItems)

    toolbar.displayMode = .iconAndLabel
    if ToolbarDisplayModeMigration.shouldApplyIconOnlyDefault(defaults: defaults) {
      toolbar.displayMode = .iconOnly
    }
    #expect(toolbar.displayMode == .iconAndLabel)
    #expect(toolbar.items.map(\.itemIdentifier) == savedItems)
    #expect(defaults.bool(forKey: ToolbarDisplayModeMigration.migrationKey))
  }

  @Test
  func firstRunDefaultDoesNotOverrideAnExistingAutosavedDisplayChoice() throws {
    let defaultsName = "NPSBrowserToolbarSavedChoice-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: defaultsName))
    defer { defaults.removePersistentDomain(forName: defaultsName) }

    let identifier = NSToolbar.Identifier("NPSBrowser.ToolbarSavedChoiceTest")
    let configurationKey = ToolbarDisplayModeMigration.configurationKeyPrefix + identifier
    defaults.set(
      ["TB Display Mode": NSToolbar.DisplayMode.iconAndLabel.rawValue],
      forKey: configurationKey
    )
    let toolbar = NSToolbar(identifier: identifier)
    toolbar.displayMode = .iconAndLabel

    #expect(
      ToolbarDisplayModeMigration.hasSavedConfiguration(identifier: identifier, defaults: defaults)
    )
    if ToolbarDisplayModeMigration.shouldApplyIconOnlyDefault(
      hasExistingSavedConfiguration: ToolbarDisplayModeMigration.hasSavedConfiguration(
        identifier: identifier,
        defaults: defaults
      ),
      defaults: defaults
    ) {
      toolbar.displayMode = .iconOnly
    }

    #expect(toolbar.displayMode == .iconAndLabel)
    #expect(defaults.bool(forKey: ToolbarDisplayModeMigration.migrationKey))
  }
}

@MainActor
private final class ToolbarMigrationTestDelegate: NSObject, NSToolbarDelegate {
  let firstIdentifier = NSToolbarItem.Identifier("ToolbarMigrationTest.First")
  let secondIdentifier = NSToolbarItem.Identifier("ToolbarMigrationTest.Second")

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [firstIdentifier, secondIdentifier]
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [firstIdentifier, secondIdentifier]
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    let item = NSToolbarItem(itemIdentifier: itemIdentifier)
    item.label = itemIdentifier.rawValue
    item.paletteLabel = item.label
    return item
  }
}
