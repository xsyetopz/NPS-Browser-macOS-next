import Testing
@testable import NPSBrowserApp

@Suite(.sourceEnglish)
struct CatalogSortTests {
  @Test
  func sortsByColumnKeyWithNaturalNumberOrdering() {
    // Arrange
    var second = browserEntry(id: "2", title: "Game 10")
    second.region = "EU"
    var first = browserEntry(id: "1", title: "Game 9")
    first.region = "US"

    // Act
    let byTitle = CatalogSort.sorted([second, first], key: "title", ascending: true)
    let byRegionDescending = CatalogSort.sorted([second, first], key: "region", ascending: false)
    let byDefaultKey = CatalogSort.sorted([second, first], key: nil, ascending: false)

    // Assert
    #expect(byTitle.map(\.id) == ["1", "2"])
    #expect(byRegionDescending.map(\.id) == ["1", "2"])
    #expect(byDefaultKey.map(\.id) == ["2", "1"])
  }

  @Test
  func unknownKeysCompareTitles() {
    // Arrange
    let entry = browserEntry(id: "A", title: "Example")

    // Act
    let value = CatalogSort.value(for: "unknown", in: entry)

    // Assert
    #expect(value == "Example")
    #expect(CatalogSort.value(for: "titleID", in: entry) == "PCSA00007")
    #expect(CatalogSort.value(for: "console", in: entry) == "PS Vita")
  }
}
