import Testing
@testable import NPSCore

@Test(.sourceEnglish)
func everyCatalogueSourceHasItsLocalizedTitle() {
  // Arrange
  let sources = CatalogSource.allCases

  // Act
  let titles = sources.map(\.localizedTitle)

  // Assert
  #expect(titles.allSatisfy { !$0.isEmpty && !$0.hasPrefix("source.") })
  #expect(CatalogSource.psvGames.localizedTitle == Localization.current.string("source.psvGames"))
  #expect(CatalogSource.psvGames.localizedTitle == "PS Vita Games")
  #expect(Set(titles).count == sources.count)
}
