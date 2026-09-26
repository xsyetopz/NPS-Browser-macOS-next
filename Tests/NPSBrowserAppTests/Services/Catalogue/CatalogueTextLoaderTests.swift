import Foundation
import NPSCore
import Testing
@testable import NPSBrowserApp

@Test(.sourceEnglish)
func readsAndParsesCatalogueFromLocalFileURL() async throws {
  let fileURL = try #require(Bundle.module.url(forResource: "LocalCatalogue", withExtension: "tsv"))
  let text = try await CatalogueTextLoader.fetchText(from: fileURL)
  let items = try CatalogParser.parseTSV(text, kind: CatalogKind(console: .PSV, fileType: .Game))

  #expect(CatalogueTextLoader.supports(fileURL))
  #expect(items.map(\.titleID) == ["PCSA00007"])
  #expect(items.first?.packageURL == URL(string: "https://example.test/preview.pkg"))
}
