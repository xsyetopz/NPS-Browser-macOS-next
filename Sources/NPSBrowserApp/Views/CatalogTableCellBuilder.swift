import AppKit

@MainActor
enum CatalogTableCellBuilder {
  static func cell(identifier: String, value: String) -> NSTableCellView {
    let label = NSTextField(labelWithString: value)
    label.lineBreakMode = .byTruncatingTail
    label.toolTip = value
    label.font =
      identifier == "titleID"
      ? .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
      : .systemFont(ofSize: NSFont.systemFontSize)
    if identifier != "title" { label.textColor = .secondaryLabelColor }
    label.translatesAutoresizingMaskIntoConstraints = false
    let cell = NSTableCellView()
    cell.textField = label
    cell.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
      label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }
}
