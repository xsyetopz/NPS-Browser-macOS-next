import Foundation
import NPSCore
import Testing
@testable import NPSBrowserApp

@Test(.sourceEnglish)
func successfulCatalogueFeedReplacesItsKindAndRetainsFailedFeedData() {
  let oldVita = makeCatalogItem(id: "old-vita", console: .PSV)
  let oldPS3 = makeCatalogItem(id: "old-ps3", console: .PS3)
  let refreshedVita = makeCatalogItem(id: "new-vita", console: .PSV)
  let updates = [
    CatalogueFeedUpdate(kind: CatalogKind(console: .PSV, fileType: .Game), items: [refreshedVita]),
    CatalogueFeedUpdate(kind: CatalogKind(console: .PS3, fileType: .Game), items: nil),
  ]

  let merged = CatalogueFeedMerger.merging(existing: [oldVita, oldPS3], updates: updates)

  #expect(Set(merged.map(\.id)) == Set([refreshedVita.id, oldPS3.id]))
}

private func makeCatalogItem(id: String, console: ConsoleType) -> CatalogItem {
  CatalogItem(
    titleID: id,
    region: "US",
    name: id,
    packageURL: URL(string: "https://example.test/\(id).pkg"),
    consoleType: console,
    fileType: .Game
  )
}
