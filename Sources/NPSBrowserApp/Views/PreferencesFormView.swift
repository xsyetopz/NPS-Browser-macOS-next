import AppKit
import NPSBrowserAppResources
import NPSCore

/// The settings form. Controls report every change through the `on…` closures,
/// so the owner can persist it immediately; `apply(_:)` never reports.
@MainActor
final class PreferencesFormView: NSView {
  var onValuesChanged: (() -> Void)?
  var onCatalogueURLCommitted: ((CatalogSource, String) -> Void)?
  var onChooseDownloadDirectory: (() -> Void)?

  let sourcePicker = NSPopUpButton()
  let sourceURLField = NSTextField()
  let validationLabel = NSTextField(wrappingLabelWithString: "")
  let directoryField = NSTextField()
  let chooseDirectoryButton = NSButton(
    title: AppResources.localized("preferences.choose"),
    target: nil,
    action: nil
  )
  let hideInvalidURLItemsSwitch = NSButton(
    checkboxWithTitle: AppResources.localized("settings.hideInvalidURLItems"),
    target: nil,
    action: nil
  )
  let concurrencyStepper = NSStepper()
  let concurrencyField = NSTextField()
  let extractSwitch = NSButton(
    checkboxWithTitle: AppResources.localized("settings.extract"),
    target: nil,
    action: nil
  )
  let keepPackageSwitch = NSButton(
    checkboxWithTitle: AppResources.localized("settings.keepPackage"),
    target: nil,
    action: nil
  )
  let saveZipSwitch = NSButton(
    checkboxWithTitle: AppResources.localized("settings.saveZip"),
    target: nil,
    action: nil
  )
  let licenseSwitch = NSButton(
    checkboxWithTitle: AppResources.localized("settings.createLicense"),
    target: nil,
    action: nil
  )
  let compressPSPSwitch = NSButton(
    checkboxWithTitle: AppResources.localized("settings.compressPSP"),
    target: nil,
    action: nil
  )
  let compressionStepper = NSStepper()
  let compressionField = NSTextField()
  var validationRow: NSGridRow?
  private var savedCatalogueURLs: [CatalogSource: URL]?
  private(set) var selectedCatalogueSource: CatalogSource?
  /// Typed URLs that differ from the saved ones, kept while switching sources.
  private var editedCatalogueURLs: [CatalogSource: String] = [:]

  init() {
    super.init(frame: .zero)
    configureControls()
    buildLayout()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  var downloadDirectoryPath: String {
    get { directoryField.stringValue }
    set { directoryField.stringValue = newValue }
  }

  /// The inline catalogue URL validation message; the row hides while it is empty.
  var validationMessage: String {
    get { validationLabel.stringValue }
    set {
      validationLabel.stringValue = newValue
      validationRow?.isHidden = newValue.isEmpty
    }
  }

  var formValues: PreferencesFormValues {
    PreferencesFormValues(
      downloadDirectoryPath: directoryField.stringValue,
      hideInvalidURLItems: hideInvalidURLItemsSwitch.state == .on,
      concurrentDownloads: concurrencyStepper.integerValue,
      extractAfterDownload: extractSwitch.state == .on,
      keepPackage: keepPackageSwitch.state == .on,
      saveAsZip: saveZipSwitch.state == .on,
      createLicense: licenseSwitch.state == .on,
      compressPSPISO: compressPSPSwitch.state == .on,
      compressionFactor: compressionStepper.integerValue
    )
  }

  /// The URL text for a source: the unsaved edit if there is one, else the saved URL.
  func catalogueURLText(for source: CatalogSource) -> String {
    if source == selectedCatalogueSource { return sourceURLField.stringValue }
    return editedCatalogueURLs[source] ?? savedCatalogueURLs?[source]?.absoluteString
      ?? source.defaultURL.absoluteString
  }

  func apply(_ preferences: BrowserPreferences) {
    savedCatalogueURLs = preferences.catalogueURLs
    editedCatalogueURLs = [:]
    selectedCatalogueSource = nil
    validationMessage = ""
    directoryField.stringValue = preferences.downloadDirectory.path
    hideInvalidURLItemsSwitch.state = preferences.hideInvalidURLItems ? .on : .off
    concurrencyStepper.integerValue = preferences.concurrentDownloads
    concurrencyField.stringValue = String(preferences.concurrentDownloads)
    extractSwitch.state = preferences.extraction.extractAfterDownload ? .on : .off
    keepPackageSwitch.state = preferences.extraction.keepPackage ? .on : .off
    saveZipSwitch.state = preferences.extraction.saveAsZip ? .on : .off
    licenseSwitch.state = preferences.extraction.createLicense ? .on : .off
    compressPSPSwitch.state = preferences.extraction.compressPSPISO ? .on : .off
    compressionStepper.integerValue = preferences.extraction.compressionFactor
    compressionField.stringValue = String(preferences.extraction.compressionFactor)
    updateCompressionControls()
    showSelectedSource()
  }

  /// Records that `url` is now saved for `source`, dropping its pending edit.
  func markCatalogueURLSaved(_ url: URL, for source: CatalogSource) {
    savedCatalogueURLs?[source] = url
    editedCatalogueURLs[source] = nil
  }

  /// Reports the URL shown in the field as committed, keeping it as an edit
  /// until the owner marks it saved.
  func commitDisplayedCatalogueURL() {
    guard let source = selectedCatalogueSource else { return }
    let text = sourceURLField.stringValue
    if text == savedCatalogueURLs?[source]?.absoluteString {
      editedCatalogueURLs[source] = nil
    } else {
      editedCatalogueURLs[source] = text
    }
    onCatalogueURLCommitted?(source, text)
  }

  @objc
  private func sourceChanged(_ sender: NSPopUpButton) {
    commitDisplayedCatalogueURL()
    showSelectedSource()
  }

  @objc
  private func catalogueURLEdited(_ sender: NSTextField) { commitDisplayedCatalogueURL() }

  @objc
  private func chooseDownloadDirectory(_ sender: NSButton) { onChooseDownloadDirectory?() }

  @objc
  private func optionChanged(_ sender: NSButton) { onValuesChanged?() }

  @objc
  private func concurrencyChanged(_ sender: NSStepper) {
    concurrencyField.stringValue = String(sender.integerValue)
    onValuesChanged?()
  }

  @objc
  private func compressionFactorChanged(_ sender: NSStepper) {
    compressionField.stringValue = String(sender.integerValue)
    onValuesChanged?()
  }

  @objc
  private func compressionOptionChanged(_ sender: NSButton) {
    updateCompressionControls()
    onValuesChanged?()
  }

  private func showSelectedSource() {
    guard savedCatalogueURLs != nil,
      CatalogSource.allCases.indices.contains(sourcePicker.indexOfSelectedItem)
    else { return }
    let source = CatalogSource.allCases[sourcePicker.indexOfSelectedItem]
    selectedCatalogueSource = nil
    sourceURLField.stringValue = catalogueURLText(for: source)
    selectedCatalogueSource = source
  }

  private func updateCompressionControls() {
    compressionStepper.isEnabled = compressPSPSwitch.state == .on
    compressionField.isEnabled = compressPSPSwitch.state == .on
  }

  private func configureControls() {
    sourcePicker.addItems(withTitles: CatalogSource.allCases.map(\.localizedTitle))
    sourcePicker.target = self
    sourcePicker.action = #selector(sourceChanged(_:))
    sourcePicker.setAccessibilityLabel(AppResources.localized("preferences.source"))
    sourceURLField.placeholderString = AppResources.localized("preferences.urlPlaceholder")
    sourceURLField.setAccessibilityLabel(AppResources.localized("preferences.url"))
    sourceURLField.target = self
    sourceURLField.action = #selector(catalogueURLEdited(_:))
    sourceURLField.cell?.sendsActionOnEndEditing = true
    sourceURLField.cell?.isScrollable = true
    sourceURLField.lineBreakMode = .byTruncatingTail

    directoryField.isEditable = false
    directoryField.isSelectable = true
    directoryField.lineBreakMode = .byTruncatingMiddle
    directoryField.setAccessibilityLabel(AppResources.localized("preferences.downloadLocation"))
    chooseDirectoryButton.bezelStyle = .rounded
    chooseDirectoryButton.target = self
    chooseDirectoryButton.action = #selector(chooseDownloadDirectory(_:))
    chooseDirectoryButton.setAccessibilityLabel(
      AppResources.localized("preferences.chooseDownloadLocation")
    )

    for option in [
      hideInvalidURLItemsSwitch, extractSwitch, keepPackageSwitch, saveZipSwitch, licenseSwitch,
    ] {
      option.target = self
      option.action = #selector(optionChanged(_:))
      option.setAccessibilityLabel(option.title)
    }
    compressPSPSwitch.target = self
    compressPSPSwitch.action = #selector(compressionOptionChanged(_:))
    compressPSPSwitch.setAccessibilityLabel(compressPSPSwitch.title)

    concurrencyStepper.minValue = 1
    concurrencyStepper.maxValue = 32
    concurrencyStepper.increment = 1
    concurrencyStepper.integerValue = 3
    concurrencyStepper.target = self
    concurrencyStepper.action = #selector(concurrencyChanged(_:))
    concurrencyStepper.setAccessibilityLabel(
      AppResources.localized("preferences.concurrentDownloads")
    )
    concurrencyField.stringValue = "3"

    compressionStepper.minValue = 0
    compressionStepper.maxValue = 9
    compressionStepper.increment = 1
    compressionStepper.target = self
    compressionStepper.action = #selector(compressionFactorChanged(_:))
    compressionStepper.setAccessibilityLabel(
      AppResources.localized("preferences.compressionFactor")
    )
    compressionField.stringValue = "1"
    for field in [concurrencyField, compressionField] {
      field.alignment = .right
      field.isEditable = false
    }

    validationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    validationLabel.textColor = .systemRed
  }
}
