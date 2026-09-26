import Foundation
import NPSCore

enum CatalogueFeed: Equatable, Sendable {
  case catalogue(CatalogKind)
  case compatibility(CompatibilityPackKind)
}
