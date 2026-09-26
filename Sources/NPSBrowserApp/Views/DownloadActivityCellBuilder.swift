import AppKit
import NPSBrowserAppResources

@MainActor
enum DownloadActivityCellBuilder {
  static func addTitle(for entry: DownloadEntry, to cell: NSTableCellView) {
    let title = NSTextField(labelWithString: entry.title)
    title.font = .systemFont(ofSize: 13, weight: .medium)
    title.lineBreakMode = .byTruncatingTail
    let detail: NSTextField
    if entry.state == .failed {
      detail = NSTextField(wrappingLabelWithString: entry.detail)
      detail.maximumNumberOfLines = 0
      detail.lineBreakMode = .byWordWrapping
    } else {
      detail = NSTextField(labelWithString: entry.detail)
      detail.lineBreakMode = .byTruncatingTail
    }
    detail.font = .systemFont(ofSize: 11)
    detail.textColor = .secondaryLabelColor
    detail.toolTip = entry.detail
    let stack = NSStackView(views: [title, detail])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
      stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
      stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
  }

  static func addState(_ stateTitle: String, to cell: NSTableCellView) {
    let label = NSTextField(labelWithString: stateTitle)
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingTail
    cell.addSubview(label)
    label.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
      label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
  }

  static func addProgress(for entry: DownloadEntry, to cell: NSTableCellView) {
    if let value = entry.progress {
      let indicator = NSProgressIndicator()
      indicator.minValue = 0
      indicator.maxValue = 1
      let normalizedProgress = min(max(value, 0), 1)
      indicator.doubleValue = normalizedProgress
      indicator.isIndeterminate = false
      indicator.style = .bar
      indicator.setAccessibilityLabel(
        String(format: AppResources.localized("downloads.progress.label"), entry.title)
      )
      // Keep the accessibility value on the same 0...1 scale as the
      // native progress indicator instead of reporting a percentage.
      indicator.setAccessibilityValue(normalizedProgress)
      cell.addSubview(indicator)
      indicator.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        indicator.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
        indicator.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
        indicator.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
    } else if entry.state == .downloading {
      let indicator = NSProgressIndicator()
      indicator.isIndeterminate = true
      indicator.style = .bar
      indicator.setAccessibilityLabel(
        String(
          format: AppResources.localized("downloads.progress.indeterminate.label"),
          entry.title
        )
      )
      indicator.setAccessibilityHelp(
        AppResources.localized("downloads.progress.indeterminate.help")
      )
      indicator.startAnimation(nil)
      cell.addSubview(indicator)
      indicator.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        indicator.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
        indicator.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
        indicator.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
    } else {
      let label = NSTextField(
        labelWithString: AppResources.localized("downloads.progress.unavailable")
      )
      label.textColor = .secondaryLabelColor
      cell.addSubview(label)
      label.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
        label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
    }
  }

  static func addActions(
    _ actions: [DownloadAction],
    for entry: DownloadEntry,
    to cell: NSTableCellView,
    titleForAction: (DownloadAction) -> String,
    target: AnyObject,
    action: Selector
  ) {
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.distribution = .fillProportionally
    stack.spacing = 5
    stack.translatesAutoresizingMaskIntoConstraints = false
    for rowAction in actions {
      let title = titleForAction(rowAction)
      let button = NSButton(title: title, target: target, action: action)
      button.bezelStyle = .rounded
      button.tag = rowAction.rawValue
      button.identifier = NSUserInterfaceItemIdentifier(entry.id)
      button.setAccessibilityLabel(
        String(format: AppResources.localized("downloads.action.accessibility"), title, entry.title)
      )
      stack.addArrangedSubview(button)
    }
    cell.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
      stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
  }
}
