import AppKit
import NPSBrowserAppResources

@MainActor
final class ItemInspectorViewController: NSViewController {
  var onDownload: (() -> Void)?
  var onDownloadRAP: ((BrowserEntry) -> Void)?
  var onDownloadUpdate: ((BrowserEntry) -> Void)?
  var onBookmark: (() -> Void)?
  private let titleLabel = NSTextField(wrappingLabelWithString: "")
  private let detailGrid = NSGridView()
  private var detailValues: [String: NSTextField] = [:]
  private let emptyStack = NSStackView()
  private let detailStack = NSStackView()
  private let downloadButton = NSButton(
    title: AppResources.localized("action.download"),
    target: nil,
    action: nil
  )
  private let downloadRAPButton = NSButton(
    title: AppResources.localized("action.downloadRAP"),
    target: nil,
    action: nil
  )
  private let downloadUpdateButton = NSButton(
    title: AppResources.localized("action.downloadUpdate"),
    target: nil,
    action: nil
  )
  private let bookmarkButton = NSButton(
    title: AppResources.localized("action.bookmark.add"),
    target: nil,
    action: nil
  )
  private(set) var currentEntry: BrowserEntry?
  private var isBookmarked = false

  var isRAPDownloadButtonVisible: Bool { !downloadRAPButton.isHidden }
  var isPackageDownloadButtonVisible: Bool { !downloadButton.isHidden }

  /// Label keys in display order; values are filled per entry and empty rows hide.
  private static let detailKeys = [
    "inspector.titleID", "inspector.console", "inspector.type", "inspector.region",
    "inspector.size", "inspector.contentID",
  ]

  override func loadView() {
    // No background: the inspector uses the window's standard background.
    let root = NSView()

    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = .labelColor
    titleLabel.maximumNumberOfLines = 4
    titleLabel.isSelectable = true

    configureDetailGrid()

    configure(downloadButton, symbol: "arrow.down.circle", key: "action.download")
    downloadButton.action = #selector(downloadAction(_:))
    // The one prominent action in the pane.
    downloadButton.bezelColor = .controlAccentColor
    configure(downloadRAPButton, symbol: "key.horizontal", key: "action.downloadRAP")
    downloadRAPButton.action = #selector(downloadRAPAction(_:))
    configure(downloadUpdateButton, symbol: "arrow.down.app", key: "action.downloadUpdate")
    downloadUpdateButton.action = #selector(downloadUpdateAction(_:))
    configure(bookmarkButton, symbol: "star", key: "action.bookmark.add")
    bookmarkButton.action = #selector(bookmarkAction(_:))

    let buttons = [downloadButton, downloadUpdateButton, downloadRAPButton, bookmarkButton]
    let buttonStack = NSStackView(views: buttons)
    buttonStack.orientation = .vertical
    buttonStack.alignment = .leading
    buttonStack.spacing = 8

    detailStack.orientation = .vertical
    detailStack.alignment = .leading
    detailStack.spacing = 16
    detailStack.addArrangedSubview(titleLabel)
    detailStack.addArrangedSubview(detailGrid)
    detailStack.addArrangedSubview(buttonStack)
    detailStack.setCustomSpacing(20, after: detailGrid)
    detailStack.translatesAutoresizingMaskIntoConstraints = false

    let emptyTitle = NSTextField(labelWithString: AppResources.localized("inspector.empty.title"))
    emptyTitle.font = .systemFont(ofSize: 15, weight: .semibold)
    emptyTitle.textColor = .secondaryLabelColor
    emptyTitle.alignment = .center
    let emptyMessage = NSTextField(
      wrappingLabelWithString: AppResources.localized("inspector.empty.message")
    )
    emptyMessage.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    emptyMessage.textColor = .tertiaryLabelColor
    emptyMessage.alignment = .center
    emptyMessage.maximumNumberOfLines = 4
    emptyStack.orientation = .vertical
    emptyStack.alignment = .centerX
    emptyStack.spacing = 6
    emptyStack.addArrangedSubview(emptyTitle)
    emptyStack.addArrangedSubview(emptyMessage)
    emptyStack.translatesAutoresizingMaskIntoConstraints = false
    emptyStack.setAccessibilityElement(true)
    emptyStack.setAccessibilityRole(.group)
    emptyStack.setAccessibilityLabel(AppResources.localized("inspector.empty.title"))

    root.addSubview(detailStack)
    root.addSubview(emptyStack)
    var constraints = [
      detailStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
      detailStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
      detailStack.topAnchor.constraint(equalTo: root.safeTopAnchor, constant: 16),
      buttonStack.widthAnchor.constraint(equalTo: detailStack.widthAnchor),
      emptyStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      emptyStack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
      emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
    ]
    // Equal-width buttons read as one group of actions.
    constraints += buttons.map { $0.widthAnchor.constraint(equalTo: buttonStack.widthAnchor) }
    NSLayoutConstraint.activate(constraints)
    view = root
    show(entry: nil, bookmarked: false)
  }

  func show(entry: BrowserEntry?, bookmarked: Bool) {
    currentEntry = entry
    isBookmarked = bookmarked
    guard let entry else {
      detailStack.isHidden = true
      emptyStack.isHidden = false
      downloadButton.isHidden = true
      downloadUpdateButton.isHidden = true
      downloadRAPButton.isHidden = true
      bookmarkButton.isHidden = false
      return
    }
    emptyStack.isHidden = true
    detailStack.isHidden = false
    downloadButton.isHidden = !entry.supportsPackageDownload
    downloadRAPButton.isHidden = !entry.supportsRAPDownload
    downloadUpdateButton.isHidden = !entry.supportsUpdateDownload
    titleLabel.stringValue = entry.title
    let size = entry.fileSize.map {
      ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
    }
    setDetails([
      "inspector.titleID": entry.titleID, "inspector.console": entry.console,
      "inspector.type": entry.category, "inspector.region": entry.region,
      "inspector.size": size ?? "", "inspector.contentID": entry.contentID ?? "",
    ])
    bookmarkButton.isHidden = entry.isCompatibilityPack
    bookmarkButton.title = AppResources.localized(
      bookmarked ? "action.bookmark.remove" : "action.bookmark.add"
    )
    bookmarkButton.setAccessibilityLabel(bookmarkButton.title)
    let bookmarkSymbol = bookmarked ? "star.fill" : "star"
    bookmarkButton.image = AppSymbols.image(
      named: bookmarkSymbol,
      description: bookmarkButton.title
    )
  }

  /// Displayed value for a detail row, or nil when that row is hidden.
  func detailValue(forKey key: String) -> String? {
    guard let field = detailValues[key], let row = Self.detailKeys.firstIndex(of: key),
      !detailGrid.row(at: row).isHidden
    else { return nil }
    return field.stringValue
  }

  private func configureDetailGrid() {
    for key in Self.detailKeys {
      let label = NSTextField(labelWithString: AppResources.localized(key))
      label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
      label.textColor = .secondaryLabelColor
      label.alignment = .right
      let value = NSTextField(wrappingLabelWithString: "")
      value.font =
        key == "inspector.contentID" || key == "inspector.titleID"
        ? .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        : .systemFont(ofSize: NSFont.smallSystemFontSize)
      value.textColor = .labelColor
      value.isSelectable = true
      value.maximumNumberOfLines = 0
      value.setAccessibilityLabel(AppResources.localized(key))
      detailValues[key] = value
      detailGrid.addRow(with: [label, value])
    }
    detailGrid.rowSpacing = 5
    detailGrid.columnSpacing = 8
    detailGrid.rowAlignment = .firstBaseline
    detailGrid.column(at: 0).xPlacement = .trailing
  }

  private func setDetails(_ values: [String: String]) {
    for (row, key) in Self.detailKeys.enumerated() {
      let value = values[key] ?? ""
      detailValues[key]?.stringValue = value
      detailGrid.row(at: row).isHidden = value.isEmpty
    }
  }

  private func configure(_ button: NSButton, symbol: String, key: String) {
    button.bezelStyle = .rounded
    button.image = AppSymbols.image(named: symbol, description: AppResources.localized(key))
    button.imagePosition = .imageLeading
    button.setAccessibilityLabel(AppResources.localized(key))
    button.target = self
  }

  @objc
  private func downloadAction(_ sender: Any?) {
    guard currentEntry?.supportsPackageDownload == true else { return }
    onDownload?()
  }
  @objc
  private func downloadRAPAction(_ sender: Any?) {
    guard let currentEntry, currentEntry.supportsRAPDownload else { return }
    onDownloadRAP?(currentEntry)
  }
  @objc
  private func downloadUpdateAction(_ sender: Any?) {
    guard let currentEntry, currentEntry.supportsUpdateDownload else { return }
    onDownloadUpdate?(currentEntry)
  }
  @objc
  private func bookmarkAction(_ sender: Any?) { onBookmark?() }
}
