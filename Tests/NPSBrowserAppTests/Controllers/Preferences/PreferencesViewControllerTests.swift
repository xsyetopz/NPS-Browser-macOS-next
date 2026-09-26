import AppKit
import Foundation
import NPSBrowserAppResources
import NPSCore
import Testing
@testable import NPSBrowserApp

@Suite(.serialized, .sourceEnglish)
@MainActor
struct PreferencesViewControllerTests {
  @Test
  func loadedPreferencesAreShownInTheForm() async throws {
    // Arrange
    let dataSource = RecordingPreferencesDataSource()
    let controller = PreferencesViewController(dataSource: dataSource)

    // Act
    let form = try #require(controller.view as? PreferencesFormView)
    try await waitForPreferencesForm(form)

    // Assert
    #expect(form.formValues.concurrentDownloads == 6)
    #expect(form.catalogueURLText(for: .psvGames) == "https://mirror.example/PSV_GAMES.tsv")
    #expect(form.formValues.hideInvalidURLItems)
    #expect(await dataSource.saveCount() == 0)
  }

  @Test
  func togglingEachCheckboxSavesImmediatelyWithoutReloadingTheCatalogue() async throws {
    // Arrange
    let (controller, form, dataSource) = try await makeLoadedController()
    var reloads = 0
    var hideChanges: [Bool] = []
    controller.onSaved = { reloads += 1 }
    controller.onHideInvalidURLItemsChanged = { hideChanges.append($0) }
    let keys = [
      "settings.hideInvalidURLItems", "settings.extract", "settings.keepPackage",
      "settings.saveZip", "settings.createLicense", "settings.compressPSP",
    ]
    let switches = try keys.map {
      try #require(button(in: form, titled: AppResources.localized($0)))
    }
    var savedAfterEachClick: [BrowserPreferences] = []

    // Act
    for toggle in switches {
      toggle.performClick(nil)
      await controller.waitForPendingSaves()
      savedAfterEachClick.append(try #require(await dataSource.savedPreferences()))
    }

    // Assert
    let saved = savedAfterEachClick
    #expect(await dataSource.saveCount() == 6)
    #expect(!saved[0].hideInvalidURLItems)
    #expect(!saved[1].extraction.extractAfterDownload)
    #expect(saved[2].extraction.keepPackage)
    #expect(saved[3].extraction.saveAsZip)
    #expect(!saved[4].extraction.createLicense)
    #expect(!saved[5].extraction.compressPSPISO)
    #expect(saved[5].extraction.unpackPS3Packages)
    #expect(
      saved[5].catalogueURLs[.psvGames] == URL(string: "https://mirror.example/PSV_GAMES.tsv")
    )
    #expect(hideChanges == [false])
    #expect(reloads == 0)
  }

  @Test
  func steppersSaveImmediately() async throws {
    // Arrange
    let (controller, form, dataSource) = try await makeLoadedController()
    let steppers = descendants(of: form).compactMap { $0 as? NSStepper }
    let concurrency = try #require(steppers.first { $0.maxValue == 32 })
    let compression = try #require(steppers.first { $0.maxValue == 9 })

    // Act
    concurrency.integerValue = 8
    concurrency.sendAction(concurrency.action, to: concurrency.target)
    compression.integerValue = 7
    compression.sendAction(compression.action, to: compression.target)
    await controller.waitForPendingSaves()

    // Assert
    let saved = try #require(await dataSource.savedPreferences())
    #expect(saved.concurrentDownloads == 8)
    #expect(saved.extraction.compressionFactor == 7)
  }

  @Test
  func choosingADownloadFolderSavesImmediately() async throws {
    // Arrange
    let (controller, form, dataSource) = try await makeLoadedController()
    var startPath: String?
    controller.chooseDirectory = { path in
      startPath = path
      return URL(fileURLWithPath: "/tmp/Chosen Downloads", isDirectory: true)
    }
    let chooseButton = try #require(
      button(in: form, titled: AppResources.localized("preferences.choose"))
    )

    // Act
    chooseButton.performClick(nil)
    await controller.waitForPendingSaves()

    // Assert
    let saved = try #require(await dataSource.savedPreferences())
    #expect(startPath == "/tmp/Loaded Downloads")
    #expect(saved.downloadDirectory.path == "/tmp/Chosen Downloads")
    #expect(form.downloadDirectoryPath == "/tmp/Chosen Downloads")
  }

  @Test
  func validCatalogueURLCommitSavesAndReloadsTheCatalogue() async throws {
    // Arrange
    let (controller, form, dataSource) = try await makeLoadedController()
    var reloads = 0
    controller.onSaved = { reloads += 1 }
    let urlField = try #require(
      textField(in: form, showing: "https://mirror.example/PSV_GAMES.tsv")
    )

    // Act
    urlField.stringValue = "file:///tmp/PSV_GAMES.tsv"
    urlField.sendAction(urlField.action, to: urlField.target)
    urlField.sendAction(urlField.action, to: urlField.target)
    await controller.waitForPendingSaves()

    // Assert
    let saved = try #require(await dataSource.savedPreferences())
    #expect(saved.catalogueURLs[.psvGames] == URL(string: "file:///tmp/PSV_GAMES.tsv"))
    #expect(await dataSource.saveCount() == 1)
    #expect(reloads == 1)
    #expect(form.validationMessage.isEmpty)
  }

  @Test
  func catalogueReloadsRunOneAtATimeForEachSavedURLChange() async throws {
    // Arrange
    let (controller, form, dataSource) = try await makeLoadedController()
    var started = 0
    var finished = 0
    var overlapped = false
    controller.onSaved = {
      started += 1
      if started - finished > 1 { overlapped = true }
      try? await Task.sleep(nanoseconds: 50_000_000)
      finished += 1
    }
    let picker = try #require(descendants(of: form).compactMap { $0 as? NSPopUpButton }.first)
    let urlField = try #require(
      textField(in: form, showing: "https://mirror.example/PSV_GAMES.tsv")
    )

    // Act
    urlField.stringValue = "https://first.example/PSV_GAMES.tsv"
    urlField.sendAction(urlField.action, to: urlField.target)
    picker.selectItem(at: try #require(CatalogSource.allCases.firstIndex(of: .ps3Games)))
    picker.sendAction(picker.action, to: picker.target)
    urlField.stringValue = "https://second.example/PS3_GAMES.tsv"
    urlField.sendAction(urlField.action, to: urlField.target)
    await controller.waitForPendingSaves()

    // Assert
    let saved = try #require(await dataSource.savedPreferences())
    #expect(saved.catalogueURLs[.psvGames] == URL(string: "https://first.example/PSV_GAMES.tsv"))
    #expect(saved.catalogueURLs[.ps3Games] == URL(string: "https://second.example/PS3_GAMES.tsv"))
    #expect(started == 2)
    #expect(finished == 2)
    #expect(!overlapped)
  }

  @Test
  func invalidCatalogueURLShowsTheInlineMessageAndIsNotSaved() async throws {
    // Arrange
    let (controller, form, dataSource) = try await makeLoadedController()
    var reloads = 0
    controller.onSaved = { reloads += 1 }
    let urlField = try #require(
      textField(in: form, showing: "https://mirror.example/PSV_GAMES.tsv")
    )

    // Act
    urlField.stringValue = "ftp://example.test/PSV_GAMES.tsv"
    urlField.sendAction(urlField.action, to: urlField.target)
    await controller.waitForPendingSaves()

    // Assert
    let expected = BrowserPreferences.ValidationFailure.invalidCatalogueURL(
      .psvGames,
      "ftp://example.test/PSV_GAMES.tsv"
    )
    #expect(form.validationMessage == expected.formMessage)
    #expect(form.validationRow?.isHidden == false)
    #expect(await dataSource.saveCount() == 0)
    #expect(reloads == 0)
    #expect(urlField.stringValue == "ftp://example.test/PSV_GAMES.tsv")
  }

  @Test
  func switchingSourcesCommitsTheEditedURL() async throws {
    // Arrange
    let (controller, form, dataSource) = try await makeLoadedController()
    let picker = try #require(descendants(of: form).compactMap { $0 as? NSPopUpButton }.first)
    let urlField = try #require(
      textField(in: form, showing: "https://mirror.example/PSV_GAMES.tsv")
    )

    // Act
    urlField.stringValue = "https://other.example/PSV_GAMES.tsv"
    picker.selectItem(at: try #require(CatalogSource.allCases.firstIndex(of: .ps3Games)))
    picker.sendAction(picker.action, to: picker.target)
    await controller.waitForPendingSaves()

    // Assert
    let saved = try #require(await dataSource.savedPreferences())
    #expect(saved.catalogueURLs[.psvGames] == URL(string: "https://other.example/PSV_GAMES.tsv"))
    #expect(urlField.stringValue == CatalogSource.ps3Games.defaultURL.absoluteString)
  }

  private func makeLoadedController() async throws -> (
    PreferencesViewController, PreferencesFormView, RecordingPreferencesDataSource
  ) {
    let dataSource = RecordingPreferencesDataSource()
    let controller = PreferencesViewController(dataSource: dataSource)
    let form = try #require(controller.view as? PreferencesFormView)
    try await waitForPreferencesForm(form)
    return (controller, form, dataSource)
  }

  private func button(in form: PreferencesFormView, titled title: String) -> NSButton? {
    descendants(of: form).compactMap { $0 as? NSButton }.first { $0.title == title }
  }

  private func textField(in form: PreferencesFormView, showing text: String) -> NSTextField? {
    descendants(of: form).compactMap { $0 as? NSTextField }.first { $0.stringValue == text }
  }
}
