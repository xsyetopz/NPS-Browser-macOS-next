import AppKit
import Foundation
import NPSBrowserAppResources
import Testing
@testable import NPSBrowserApp

@Suite(.serialized, .sourceEnglish)
@MainActor
struct BrowserViewControllerTests {
  @Test
  func windowTitleNamesTheSectionAndSubtitleCarriesTheCount() async throws {
    // Arrange
    let entry = layoutEntry(id: "layout-title", title: "Layout Title Game")
    let controller = BrowserWindowController(
      dataSource: EmptyBrowserDataSource(previewEntries: [entry])
    )
    let window = try #require(controller.window)
    defer { window.close() }
    let browser = controller.browserViewController
    _ = browser.view
    browser.viewWillAppear()

    // Act
    try await waitUntil { browser.catalogueController.summary.subtitle.contains("1") }
    browser.viewWillAppear()

    // Assert
    #expect(window.title == AppResources.localized("section.all"))
    if #available(macOS 11.0, *) {
      #expect(window.subtitle == CountText.string(1, key: "status.items"))
    }
    browser.showDownloads(nil)
    #expect(window.title == AppResources.localized("section.downloads"))
    if #available(macOS 11.0, *) {
      #expect(window.subtitle == CountText.string(0, key: "downloads.count"))
    }
  }

  @Test
  func hiddenInspectorStaysHiddenAfterVisitingDownloads() {
    // Arrange
    let key = InterfacePreferences.inspectorHiddenKey
    let previous = UserDefaults.standard.object(forKey: key)
    UserDefaults.standard.removeObject(forKey: key)
    defer { UserDefaults.standard.set(previous, forKey: key) }
    let browser = BrowserViewController(dataSource: EmptyBrowserDataSource())
    _ = browser.view
    // Appearance applies the stored choice over the split view's autosave.
    browser.viewWillAppear()
    #expect(browser.isInspectorVisible)

    // Act
    browser.toggleInspectorPane(nil)
    browser.showDownloads(nil)
    browser.showAllItems(nil)

    // Assert: the choice survives Downloads and a new window's appearance.
    #expect(!browser.isInspectorVisible)
    browser.viewWillAppear()
    #expect(!browser.isInspectorVisible)
    browser.toggleInspectorPane(nil)
    browser.viewWillAppear()
    #expect(browser.isInspectorVisible)
  }

  @Test
  func forcedReloadsRequestedDuringALoadRunOnceAfterIt() async {
    // Arrange
    let dataSource = GatedReloadDataSource()
    let browser = BrowserViewController(dataSource: dataSource)
    let launch = Task { await browser.reloadData(forceRefresh: false) }
    await dataSource.waitUntilGated()

    // Act
    let settings = Task { await browser.reloadData(forceRefresh: true) }
    let manual = Task { await browser.reloadData(forceRefresh: true) }
    await Task.yield()
    let refreshesWhileGated = await dataSource.refreshCount()
    await dataSource.release()
    await settings.value
    let refreshesWhenSettingsReturned = await dataSource.refreshCount()
    await manual.value
    await launch.value

    // Assert
    #expect(refreshesWhileGated == 0)
    #expect(refreshesWhenSettingsReturned == 1)
    #expect(await dataSource.refreshCount() == 1)
  }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
  for _ in 0..<200 {
    if condition() { return }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  Issue.record("Timed out waiting for the layout condition")
}
