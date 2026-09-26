import AppKit
import NPSBrowserAppResources

extension PreferencesFormView {
  private static let controlWidth: CGFloat = 360
  private static let valueFieldWidth: CGFloat = 40
  private static let sectionSpacing: CGFloat = 14

  /// Lays the form out as a two-column grid: right-aligned labels, leading controls.
  func buildLayout() {
    sourceURLField.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
    validationLabel.preferredMaxLayoutWidth = Self.controlWidth
    concurrencyField.widthAnchor.constraint(equalToConstant: Self.valueFieldWidth).isActive = true
    compressionField.widthAnchor.constraint(equalToConstant: Self.valueFieldWidth).isActive = true
    let directoryStack = NSStackView(views: [directoryField, chooseDirectoryButton])
    directoryStack.orientation = .horizontal
    directoryStack.alignment = .firstBaseline
    directoryStack.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
    directoryStack.distribution = .fill
    directoryField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    directoryField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let ps3Note = NSTextField(
      wrappingLabelWithString: AppResources.localized("preferences.ps3ExtractionNote")
    )
    ps3Note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    ps3Note.textColor = .secondaryLabelColor
    ps3Note.preferredMaxLayoutWidth = Self.controlWidth

    let empty = NSGridCell.emptyContentView
    let concurrencyStack = valueStack(concurrencyField, concurrencyStepper)
    let compressionStack = valueStack(compressionField, compressionStepper)
    let grid = NSGridView()
    grid.addRow(with: [Self.label("settings.form.source"), sourcePicker])
    grid.addRow(with: [Self.label("settings.form.url"), sourceURLField])
    validationRow = grid.addRow(with: [empty, validationLabel])
    grid.addRow(with: [empty, hideInvalidURLItemsSwitch])
    grid.addRow(with: [Self.label("settings.form.downloadLocation"), directoryStack]).topPadding =
      Self.sectionSpacing
    grid.addRow(with: [Self.label("settings.form.concurrentDownloads"), concurrencyStack])
    grid.addRow(with: [Self.label("settings.form.afterDownload"), extractSwitch]).topPadding =
      Self.sectionSpacing
    for option in [keepPackageSwitch, saveZipSwitch, licenseSwitch, compressPSPSwitch] {
      grid.addRow(with: [empty, option])
    }
    grid.addRow(with: [Self.label("settings.form.compressionFactor"), compressionStack])
    grid.addRow(with: [empty, ps3Note])
    grid.translatesAutoresizingMaskIntoConstraints = false
    grid.rowAlignment = .firstBaseline
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .leading
    grid.rowSpacing = 8
    grid.columnSpacing = 8
    validationRow?.isHidden = true
    addSubview(grid)
    NSLayoutConstraint.activate([
      grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
      grid.topAnchor.constraint(equalTo: topAnchor, constant: 20),
      grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
    ])
  }

  private func valueStack(_ field: NSTextField, _ stepper: NSStepper) -> NSStackView {
    let stack = NSStackView(views: [field, stepper])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 4
    return stack
  }

  private static func label(_ key: String) -> NSTextField {
    let label = NSTextField(labelWithString: AppResources.localized(key))
    label.alignment = .right
    return label
  }
}
