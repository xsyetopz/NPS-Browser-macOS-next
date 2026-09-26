import AppKit

extension NSView {
  /// Top edge below a full-size-content toolbar on macOS 11+; the view top on 10.15,
  /// where the window keeps a separate title bar.
  var safeTopAnchor: NSLayoutYAxisAnchor {
    if #available(macOS 11.0, *) { return safeAreaLayoutGuide.topAnchor }
    return topAnchor
  }
}
