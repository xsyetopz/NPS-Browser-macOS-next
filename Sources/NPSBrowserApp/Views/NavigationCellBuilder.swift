import AppKit
import NPSBrowserAppResources

@MainActor
enum NavigationCellBuilder {
  static func headingCell(titleKey: String) -> NSTextField {
    let cell = NSTextField(labelWithString: AppResources.localized(titleKey))
    cell.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold)
    cell.textColor = .secondaryLabelColor
    cell.lineBreakMode = .byTruncatingTail
    cell.setAccessibilityElement(true)
    cell.setAccessibilityRole(.staticText)
    cell.setAccessibilityLabel(AppResources.localized(titleKey))
    return cell
  }

  static func sectionCell(for section: BrowserSection) -> NSTableCellView {
    // imageView/textField let the source list apply its row metrics,
    // accent-tinted icons and selection text colors.
    let cell = NSTableCellView()
    let image = NSImageView()
    image.image = AppSymbols.image(
      named: section.symbolName,
      description: AppResources.localized(section.titleKey)
    )
    image.imageScaling = .scaleProportionallyUpOrDown
    image.translatesAutoresizingMaskIntoConstraints = false
    image.setContentHuggingPriority(.required, for: .horizontal)
    let label = NSTextField(labelWithString: AppResources.localized(section.navigationTitleKey))
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.imageView = image
    cell.textField = label
    cell.addSubview(image)
    cell.addSubview(label)
    NSLayoutConstraint.activate([
      image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
      image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      image.widthAnchor.constraint(equalToConstant: 18),
      image.heightAnchor.constraint(equalToConstant: 16),
      label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
      label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    cell.setAccessibilityElement(true)
    cell.setAccessibilityLabel(AppResources.localized(section.titleKey))
    return cell
  }
}
