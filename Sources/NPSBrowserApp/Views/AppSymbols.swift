import AppKit

enum AppSymbols {
  static func image(named name: String, description: String) -> NSImage? {
    if #available(macOS 11.0, *) {
      if let image = NSImage(systemSymbolName: name, accessibilityDescription: description) {
        return image
      }
    }
    return fallbackImage(named: name, description: description)
  }

  static func fallbackImage(named name: String, description: String) -> NSImage? {
    let supportedNames: Set<String> = [
      "star", "star.fill", "arrow.down.circle", "list.bullet.rectangle", "square.grid.2x2",
      "gamecontroller", "arrow.down.app", "puzzlepiece", "paintbrush", "person.crop.square",
      "shippingbox", "shippingbox.fill", "key.horizontal", "sidebar.right",
    ]
    guard supportedNames.contains(name) else { return nil }
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { bounds in
      let color = NSColor.controlTextColor
      color.setStroke()
      color.setFill()
      return drawFallbackSymbol(named: name, in: bounds)
    }
    image.isTemplate = true
    image.accessibilityDescription = description
    return image
  }
}
