import Foundation

enum CatalogSort {
  static func sorted(_ entries: [BrowserEntry], key: String?, ascending: Bool) -> [BrowserEntry] {
    let key = key ?? "title"
    return entries.sorted { lhs, rhs in
      let lhsValue = value(for: key, in: lhs)
      let rhsValue = value(for: key, in: rhs)
      return ascending
        ? lhsValue.localizedStandardCompare(rhsValue) == .orderedAscending
        : lhsValue.localizedStandardCompare(rhsValue) == .orderedDescending
    }
  }

  static func value(for key: String, in entry: BrowserEntry) -> String {
    switch key {
    case "console": entry.console
    case "titleID": entry.titleID
    case "region": entry.region
    default: entry.title
    }
  }
}
