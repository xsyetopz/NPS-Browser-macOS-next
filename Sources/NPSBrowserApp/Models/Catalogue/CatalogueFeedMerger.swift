import Foundation
import NPSCore

enum CatalogueFeedMerger {
  /// Replaces each successful source while retaining persisted entries for failed sources.
  /// The caller stores the merged result in one Realm write transaction.
  static func merging(existing: [CatalogItem], updates: [CatalogueFeedUpdate]) -> [CatalogItem] {
    let replacedKinds = Set(updates.filter { $0.items != nil }.map(\.kind))
    let retained = existing.filter {
      !replacedKinds.contains(CatalogKind(console: $0.consoleType, fileType: $0.fileType))
    }
    let refreshed = updates.compactMap(\.items).flatMap { $0 }
    return retained + refreshed
  }
}
