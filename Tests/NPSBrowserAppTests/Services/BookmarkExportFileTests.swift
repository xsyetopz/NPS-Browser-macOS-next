import Foundation
import NPSCore
import Testing
@testable import NPSBrowserApp

@Test(.sourceEnglish)
func bookmarkExportIncludesPersistedOrphanRecord() {
  let orphan = Bookmark(
    id: "legacy-orphan",
    titleID: "PCSE00001",
    downloadURL: URL(string: "https://example.test/orphan.pkg"),
    name: "Removed from feed",
    fileType: "Game",
    consoleType: "PSV",
    zrif: nil
  )

  let csv = Bookmark.csv([orphan])

  #expect(csv.contains("legacy-orphan"))
  #expect(csv.contains("Removed from feed"))
  #expect(csv.contains("PCSE00001"))
}
