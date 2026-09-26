import Testing
@testable import NPSBrowserApp

@Test(.sourceEnglish)
func searchMissUsesSearchSpecificEmptyState() {
  let state = CatalogEmptyState.forFilter(section: .allItems, query: "not-found")

  #expect(state.titleKey == "empty.search.title")
  #expect(state.messageKey == "empty.search.message")
}
