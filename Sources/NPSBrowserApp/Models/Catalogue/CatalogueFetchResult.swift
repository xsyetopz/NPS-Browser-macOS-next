import Foundation
import NPSCore

struct CatalogueFetchResult: Sendable {
  let request: CatalogueRequest
  let items: [CatalogItem]
  let compatibilityPacks: [CompatibilityPack]
  let error: LocalizedMessage?
}
