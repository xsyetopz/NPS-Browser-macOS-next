import Foundation
import NPSBrowserAppResources

enum CountText {
  /// "36,432 items" / "1 item": the catalog's plural form, grouped for the UI language.
  static func string(_ count: Int, key: String) -> String { AppResources.plural(key, count: count) }
}
