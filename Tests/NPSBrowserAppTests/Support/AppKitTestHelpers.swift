import AppKit

@MainActor
func descendants(of view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

@MainActor
func menuItem(action: Selector) -> NSMenuItem {
  NSMenuItem(title: "", action: action, keyEquivalent: "")
}
