import Foundation

/// Interface layout choices the user makes, kept across launches.
struct InterfacePreferences {
  static let inspectorHiddenKey = "NPSBrowser.InspectorHidden"

  var defaults: UserDefaults = .standard

  var isInspectorHidden: Bool {
    get { defaults.bool(forKey: Self.inspectorHiddenKey) }
    nonmutating set { defaults.set(newValue, forKey: Self.inspectorHiddenKey) }
  }
}
