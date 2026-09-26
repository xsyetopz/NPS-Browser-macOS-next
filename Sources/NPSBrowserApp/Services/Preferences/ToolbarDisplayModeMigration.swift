import Foundation

/// Records the icon-only toolbar default once per toolbar identifier, without
/// overriding a display mode the user already saved.
enum ToolbarDisplayModeMigration {
  static let migrationKey = "NPSBrowser.MainToolbar.v2.iconOnlyDefaultApplied"
  static let configurationKeyPrefix = "NSToolbar Configuration "

  static func hasSavedConfiguration(identifier: String, defaults: UserDefaults = .standard) -> Bool
  { defaults.object(forKey: configurationKeyPrefix + identifier) != nil }

  static func shouldApplyIconOnlyDefault(
    hasExistingSavedConfiguration: Bool = false,
    defaults: UserDefaults = .standard
  ) -> Bool {
    guard defaults.object(forKey: migrationKey) == nil else { return false }
    defaults.set(true, forKey: migrationKey)
    return !hasExistingSavedConfiguration
  }
}
