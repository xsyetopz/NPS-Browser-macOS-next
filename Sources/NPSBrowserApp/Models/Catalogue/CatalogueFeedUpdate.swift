import Foundation
import NPSCore

struct CatalogueFeedUpdate: Sendable {
  let kind: CatalogKind
  /// `nil` marks a failed source; an empty successful source is also distinguishable.
  let items: [CatalogItem]?
}
