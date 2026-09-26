import AppKit
import Foundation
import NPSBrowserAppResources
import NPSCore
import Testing
@testable import NPSBrowserApp

@Suite(.serialized, .sourceEnglish)
@MainActor
struct PreferencesFormViewTests {
  @Test
  func appliedPreferencesRoundTripThroughFormValues() throws {
    // Arrange
    let preferences = makeFormPreferences()
    let form = PreferencesFormView()

    // Act
    form.apply(preferences)
    let updated = try preferences.applying(form.formValues).get()

    // Assert
    #expect(
      CatalogSource.allCases.map { form.catalogueURLText(for: $0) }
        == CatalogSource.allCases.map { preferences.catalogueURLs[$0]?.absoluteString }
    )
    #expect(form.downloadDirectoryPath == "/tmp/NPS Downloads")
    #expect(updated.catalogueURLs == preferences.catalogueURLs)
    #expect(updated.extraction.compressionFactor == 4)
    #expect(updated.downloadDirectory.path == preferences.downloadDirectory.path)
    #expect(updated.concurrentDownloads == 5)
    #expect(updated.hideInvalidURLItems == preferences.hideInvalidURLItems)
    #expect(updated.extraction == preferences.extraction)
  }

  @Test
  func editedSourceURLIsKeptWhenSwitchingSources() throws {
    // Arrange
    let form = PreferencesFormView()
    form.apply(makeFormPreferences())
    let picker = try #require(descendants(of: form).compactMap { $0 as? NSPopUpButton }.first)
    let urlField = try #require(
      descendants(of: form).compactMap { $0 as? NSTextField }.first {
        $0.stringValue == CatalogSource.psvGames.defaultURL.absoluteString
      }
    )

    // Act
    urlField.stringValue = "https://mirror.example/PSV_GAMES.tsv"
    picker.selectItem(at: CatalogSource.allCases.firstIndex(of: .ps3Games)!)
    picker.sendAction(picker.action, to: picker.target)

    // Assert
    #expect(urlField.stringValue == CatalogSource.ps3Games.defaultURL.absoluteString)
    #expect(form.catalogueURLText(for: .psvGames) == "https://mirror.example/PSV_GAMES.tsv")
  }

  @Test
  func compressionFactorControlsFollowTheCompressionOption() throws {
    // Arrange
    var preferences = makeFormPreferences()
    preferences.extraction.compressPSPISO = false
    let form = PreferencesFormView()

    // Act
    form.apply(preferences)

    // Assert
    let steppers = descendants(of: form).compactMap { $0 as? NSStepper }
    let compressionStepper = try #require(steppers.first { $0.maxValue == 9 })
    #expect(!compressionStepper.isEnabled)
    #expect(!form.formValues.compressPSPISO)
  }
}

extension PreferencesFormViewTests {
  @Test
  func controlChangesAreReportedAndApplyingIsSilent() throws {
    // Arrange
    let form = PreferencesFormView()
    var changeCount = 0
    form.onValuesChanged = { changeCount += 1 }
    form.apply(makeFormPreferences())
    let checkboxes = descendants(of: form).compactMap { $0 as? NSButton }.filter {
      !($0 is NSPopUpButton) && $0.target === form
        && $0.title != AppResources.localized("preferences.choose")
    }
    let steppers = descendants(of: form).compactMap { $0 as? NSStepper }
    let concurrencyStepper = try #require(steppers.first { $0.maxValue == 32 })

    // Act
    let countAfterApply = changeCount
    checkboxes.forEach { $0.performClick(nil) }
    concurrencyStepper.integerValue = 9
    concurrencyStepper.sendAction(concurrencyStepper.action, to: concurrencyStepper.target)

    // Assert
    #expect(countAfterApply == 0)
    #expect(checkboxes.count == 6)
    #expect(changeCount == 7)
    #expect(form.formValues.concurrentDownloads == 9)
    #expect(
      descendants(of: form).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "9" }
    )
  }

  @Test
  func committingTheURLFieldReportsTheSelectedSourceAndText() throws {
    // Arrange
    let form = PreferencesFormView()
    form.apply(makeFormPreferences())
    var commits: [(CatalogSource, String)] = []
    form.onCatalogueURLCommitted = { commits.append(($0, $1)) }
    let urlField = try #require(
      descendants(of: form).compactMap { $0 as? NSTextField }.first {
        $0.stringValue == CatalogSource.psvGames.defaultURL.absoluteString
      }
    )

    // Act
    urlField.stringValue = "https://mirror.example/PSV_GAMES.tsv"
    urlField.sendAction(urlField.action, to: urlField.target)

    // Assert
    #expect(urlField.cell?.sendsActionOnEndEditing == true)
    #expect(commits.map(\.0) == [.psvGames])
    #expect(commits.map(\.1) == ["https://mirror.example/PSV_GAMES.tsv"])
  }

  @Test
  func validationMessageShowsInlineOnlyWhileSet() throws {
    // Arrange
    let form = PreferencesFormView()
    form.apply(makeFormPreferences())
    let grid = try #require(descendants(of: form).compactMap { $0 as? NSGridView }.first)
    let message = BrowserPreferences.ValidationFailure.invalidCatalogueURL(.psvGames, "x")
      .formMessage

    // Act
    let hiddenBefore = form.validationRow?.isHidden
    form.validationMessage = message
    let shownRowHidden = form.validationRow?.isHidden
    form.validationMessage = ""

    // Assert
    #expect(hiddenBefore == true)
    #expect(shownRowHidden == false)
    #expect(form.validationRow?.isHidden == true)
    #expect(descendants(of: grid).contains { ($0 as? NSTextField)?.textColor == .systemRed })
  }

  @Test
  func formHasNoHeadingOrSaveAndCancelButtons() {
    // Arrange
    let form = PreferencesFormView()
    let switches = [
      form.hideInvalidURLItemsSwitch, form.extractSwitch, form.keepPackageSwitch,
      form.saveZipSwitch, form.licenseSwitch, form.compressPSPSwitch,
    ]

    // Act
    let buttons = descendants(of: form).compactMap { $0 as? NSButton }
    let pushButtons = buttons.filter { button in
      !(button is NSPopUpButton) && !switches.contains { $0 === button }
    }

    // Assert: the grid is the only top-level view, so there is no heading above it,
    // and the only push button is Choose…, so there is no Save or Cancel.
    #expect(!buttons.contains { $0.keyEquivalent == "\r" || $0.keyEquivalent == "\u{1b}" })
    #expect(pushButtons.count == 1)
    #expect(pushButtons.first === form.chooseDirectoryButton)
    #expect(form.subviews.count == 1)
    #expect(form.subviews.first is NSGridView)
  }
}

private func makeFormPreferences() -> BrowserPreferences {
  BrowserPreferences(
    catalogueURLs: Dictionary(
      uniqueKeysWithValues: CatalogSource.allCases.map { ($0, $0.defaultURL) }
    ),
    downloadDirectory: URL(fileURLWithPath: "/tmp/NPS Downloads", isDirectory: true),
    concurrentDownloads: 5,
    extraction: ExtractionSettings(
      extractAfterDownload: false,
      keepPackage: true,
      saveAsZip: true,
      createLicense: false,
      compressPSPISO: true,
      compressionFactor: 4,
      unpackPS3Packages: false
    ),
    hideInvalidURLItems: false
  )
}
