import Foundation
import NPSCore

public enum AppResources {
  public static func localized(_ key: String) -> String { Localization.current.string(key) }

  /// Formats `count` through the catalog's `.stringsdict` plural for `key`.
  public static func plural(_ key: String, count: Int) -> String {
    Localization.current.plural(key, count: count)
  }
}
