import AppKit
import Foundation
import NPSBrowserAppResources
import NPSCore
import Testing
@testable import NPSBrowserApp

@Suite(.serialized, .sourceEnglish)
@MainActor
struct PreferencesWindowControllerTests {
  @Test
  func windowIsAFixedSizeSettingsWindowSizedToItsContent() throws {
    // Arrange
    let controller = PreferencesWindowController(dataSource: RecordingPreferencesDataSource()) {}

    // Act
    let window = try #require(controller.window)
    defer { window.close() }

    // Assert
    #expect(window.styleMask.contains(.titled))
    #expect(window.styleMask.contains(.closable))
    #expect(!window.styleMask.contains(.resizable))
    #expect(!window.styleMask.contains(.miniaturizable))
    #expect(!window.isReleasedWhenClosed)
    #expect(controller.windowFrameAutosaveName == PreferencesWindowController.frameAutosaveName)
    let fitting = controller.preferencesViewController.view.fittingSize
    #expect(
      window.contentLayoutRect.size
        == NSSize(width: fitting.width.rounded(.up), height: fitting.height.rounded(.up))
    )
    if #available(macOS 13.0, *) {
      #expect(window.title == AppResources.localized("settings.title"))
    } else {
      #expect(window.title == AppResources.localized("preferences.title"))
    }
  }

  @Test
  func closingTheWindowCommitsAPendingValidURLEdit() async throws {
    // Arrange
    let dataSource = RecordingPreferencesDataSource()
    var reloads = 0
    let controller = PreferencesWindowController(dataSource: dataSource) { reloads += 1 }
    let window = try #require(controller.window)
    let form = try #require(controller.preferencesViewController.view as? PreferencesFormView)
    try await waitForPreferencesForm(form)
    let urlField = try #require(
      descendants(of: form).compactMap { $0 as? NSTextField }.first {
        $0.stringValue == "https://mirror.example/PSV_GAMES.tsv"
      }
    )
    controller.showWindow(nil)
    #expect(window.makeFirstResponder(urlField))
    let editor = try #require(urlField.currentEditor() as? NSTextView)
    editor.selectAll(nil)
    editor.insertText(
      "https://closing.example/PSV_GAMES.tsv",
      replacementRange: editor.selectedRange()
    )

    // Act
    window.performClose(nil)
    await controller.preferencesViewController.waitForPendingSaves()

    // Assert
    let saved = try #require(await dataSource.savedPreferences())
    #expect(saved.catalogueURLs[.psvGames] == URL(string: "https://closing.example/PSV_GAMES.tsv"))
    #expect(reloads == 1)
    #expect(!window.isVisible)
  }
}
