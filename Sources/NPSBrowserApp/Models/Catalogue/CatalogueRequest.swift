import Foundation
import NPSCore

struct CatalogueRequest: Sendable {
  let source: CatalogSource
  let feed: CatalogueFeed
  let url: URL
}
