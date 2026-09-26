import Foundation
import NPSCore

extension ApplicationDataSource {
  func loadCatalogue() async throws -> [BrowserEntry] {
    let items = try await catalogue.allItems().map(BrowserEntry.init(item:))
    let compatibilityPacks = try await catalogue.compatibilityPacks()
    return items + Self.compatibilityEntries(from: compatibilityPacks)
  }

  func refreshCatalogue() async throws -> [BrowserEntry] {
    let snapshot = settings.snapshot()
    let catalogueRequests = Self.supportedSources.compactMap { source, kind -> CatalogueRequest? in
      guard let url = snapshot.catalogueURLs[source] else { return nil }
      return CatalogueRequest(source: source, feed: .catalogue(kind), url: url)
    }
    let compatibilityRequests = Self.compatibilitySources.compactMap {
      source,
      kind -> CatalogueRequest? in
      guard let url = snapshot.catalogueURLs[source] else { return nil }
      return CatalogueRequest(source: source, feed: .compatibility(kind), url: url)
    }
    let requests = catalogueRequests + compatibilityRequests

    let results = await withTaskGroup(
      of: CatalogueFetchResult.self,
      returning: [CatalogueFetchResult].self
    ) { group in
      for request in requests {
        group.addTask {
          do {
            let text = try await CatalogueTextLoader.fetchText(from: request.url)
            switch request.feed {
            case .catalogue(let kind):
              return CatalogueFetchResult(
                request: request,
                items: try CatalogParser.parseTSV(text, kind: kind),
                compatibilityPacks: [],
                error: nil
              )
            case .compatibility(let kind):
              return CatalogueFetchResult(
                request: request,
                items: [],
                compatibilityPacks: try CatalogParser.parseCompatibilityPacks(text, kind: kind),
                error: nil
              )
            }
          } catch {
            return CatalogueFetchResult(
              request: request,
              items: [],
              compatibilityPacks: [],
              error: LocalizedMessage(error)
            )
          }
        }
      }
      var values: [CatalogueFetchResult] = []
      for await value in group { values.append(value) }
      return values
    }

    let failures = results.compactMap { result in
      result.error.map { CatalogueSourceFailure(source: result.request.source, reason: $0) }
    }

    let catalogueResults = results.filter {
      if case .catalogue = $0.request.feed { return true }
      return false
    }
    let feedUpdates = catalogueResults.compactMap { result -> CatalogueFeedUpdate? in
      guard case .catalogue(let kind) = result.request.feed else { return nil }
      return CatalogueFeedUpdate(kind: kind, items: result.error == nil ? result.items : nil)
    }
    if feedUpdates.contains(where: { $0.items != nil }) {
      let existingItems = try await catalogue.allItems()
      let mergedItems = CatalogueFeedMerger.merging(existing: existingItems, updates: feedUpdates)
      try await catalogue.replaceItems(mergedItems)
    }
    for kind in CompatibilityPackKind.allCases {
      let kindResults = results.filter { $0.request.feed == .compatibility(kind) }
      guard !kindResults.isEmpty, kindResults.allSatisfy({ $0.error == nil }) else { continue }
      try await catalogue.replaceCompatibilityPacks(
        kindResults.flatMap(\.compatibilityPacks),
        kind: kind
      )
    }
    guard failures.isEmpty else { throw CatalogueRefreshError.partialFailure(failures) }
    return try await loadCatalogue()
  }
  static let supportedSources: [(CatalogSource, CatalogKind)] = [
    (.psvGames, CatalogKind(console: .PSV, fileType: .Game)),
    (.psvDLCs, CatalogKind(console: .PSV, fileType: .DLC)),
    (.psvThemes, CatalogKind(console: .PSV, fileType: .Theme)),
    (.psmGames, CatalogKind(console: .PSM, fileType: .Game)),
    (.pspGames, CatalogKind(console: .PSP, fileType: .Game)),
    (.pspDLCs, CatalogKind(console: .PSP, fileType: .DLC)),
    (.psxGames, CatalogKind(console: .PSX, fileType: .Game)),
    (.ps3Games, CatalogKind(console: .PS3, fileType: .Game)),
    (.ps3DLCs, CatalogKind(console: .PS3, fileType: .DLC)),
    (.ps3Themes, CatalogKind(console: .PS3, fileType: .Theme)),
    (.ps3Avatars, CatalogKind(console: .PS3, fileType: .Avatar)),
  ]

  private static let compatibilitySources: [(CatalogSource, CompatibilityPackKind)] = [
    (.compatPacks, .pack), (.compatPatch, .patch),
  ]
}
