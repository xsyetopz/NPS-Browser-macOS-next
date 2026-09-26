import Foundation
import Testing
@testable import NPSBrowserApp

@Test(.sourceEnglish)
func filtersByConsoleCategory() {
  let entries = [
    makeEntry(id: "A", title: "Game A", console: "PS3"),
    makeEntry(id: "B", title: "Game B", console: "PS Vita"),
  ]

  let filtered = CatalogFilter.matching(entries, section: .ps3, bookmarkedIDs: [], query: "")

  #expect(filtered.map(\.id) == ["A"])
}

@Test(.sourceEnglish)
func searchesTitleIDAndBookmarkSubset() {
  let entries = [
    makeEntry(id: "A", title: "Blue Game", console: "PS3"),
    makeEntry(id: "B", title: "Red Game", console: "PS3"),
  ]

  let filtered = CatalogFilter.matching(
    entries,
    section: .bookmarks,
    bookmarkedIDs: ["B"],
    query: "IDB"
  )

  #expect(filtered.map(\.id) == ["B"])
}

@Test(.sourceEnglish)
func filtersByContentCategory() {
  let entries = [
    makeEntry(id: "A", title: "Game", console: "PS3", category: "Game"),
    makeEntry(id: "B", title: "Add-on", console: "PS3", category: "DLC"),
  ]

  let filtered = CatalogFilter.matching(entries, section: .dlc, bookmarkedIDs: [], query: "")

  #expect(filtered.map(\.id) == ["B"])
}

@Test(.sourceEnglish)
func filtersCompatibilityPacksSeparatelyFromPatches() {
  let entries = [
    makeEntry(id: "pack", title: "RePatch Pack", console: "PS Vita", category: "CPack"),
    makeEntry(id: "patch", title: "RePatch Patch", console: "PS Vita", category: "CPatch"),
  ]

  let filtered = CatalogFilter.matching(
    entries,
    section: .compatPatches,
    bookmarkedIDs: [],
    query: ""
  )

  #expect(filtered.map(\.id) == ["patch"])
}

@Test(.sourceEnglish)
func hideInvalidURLSettingControlsItemsWithoutPackageLinks() {
  let entries = [
    makeEntry(id: "valid", title: "Valid", console: "PS3"),
    makeEntry(id: "missing", title: "Missing package", console: "PS3", packageURL: nil),
  ]

  let hidden = CatalogFilter.matching(
    entries,
    section: .allItems,
    bookmarkedIDs: [],
    query: "",
    hideInvalidURLItems: true
  )
  let shown = CatalogFilter.matching(
    entries,
    section: .allItems,
    bookmarkedIDs: [],
    query: "",
    hideInvalidURLItems: false
  )

  #expect(hidden.map(\.id) == ["valid"])
  #expect(shown.map(\.id) == ["valid", "missing"])
}

@Test(.sourceEnglish)
func defaultFilterKeepsPS3EntriesThatCanDownloadRAPWithoutPackageURL() {
  let rapOnly = makeEntry(
    id: "rap-only",
    title: "License-only item",
    console: "PS3",
    packageURL: nil,
    titleID: "NPUB12345",
    rapDownloadURL: URL(string: "https://nopaystation.com/tools/rap2file/CONTENT/ABCD")
  )
  let unavailable = makeEntry(
    id: "unavailable",
    title: "Unavailable",
    console: "PS3",
    packageURL: nil
  )

  let filtered = CatalogFilter.matching(
    [rapOnly, unavailable],
    section: .allItems,
    bookmarkedIDs: [],
    query: ""
  )

  #expect(filtered.map(\.id) == ["rap-only"])
}

@Test(.sourceEnglish)
func updatesSectionListsVitaGamesThatCanBeChecked() {
  let entries = [
    makeEntry(id: "vita", title: "Vita Game", console: "PS Vita"),
    makeEntry(id: "ps3", title: "PS3 Game", console: "PS3"),
    makeEntry(id: "vita-dlc", title: "Vita DLC", console: "PS Vita", category: "DLC"),
  ]

  let updates = CatalogFilter.matching(entries, section: .updates, bookmarkedIDs: [], query: "")

  #expect(updates.map(\.id) == ["vita"])
}

private func makeEntry(
  id: String,
  title: String,
  console: String,
  category: String = "Game",
  packageURL: URL? = URL(string: "https://example.test/game.pkg"),
  titleID: String? = nil,
  rapDownloadURL: URL? = nil
) -> BrowserEntry {
  BrowserEntry(
    id: id,
    title: title,
    titleID: titleID ?? "ID\(id)",
    console: console,
    consoleCode: console == "PS Vita" ? "PSV" : console == "PS3" ? "PS3" : "",
    category: category,
    region: "US",
    fileSize: nil,
    packageURL: packageURL,
    rapDownloadURL: rapDownloadURL,
    sha256: nil,
    contentID: nil
  )
}
