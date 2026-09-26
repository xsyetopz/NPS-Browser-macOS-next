import Foundation
@testable import NPSBrowserApp

func browserEntry(id: String, title: String) -> BrowserEntry {
  BrowserEntry(
    id: id,
    title: title,
    titleID: "PCSA00007",
    console: "PS Vita",
    consoleCode: "PSV",
    category: "Game",
    region: "US",
    fileSize: nil,
    packageURL: URL(string: "https://example.test/\(id).pkg"),
    sha256: nil,
    contentID: nil
  )
}

func layoutEntry(id: String, title: String) -> BrowserEntry {
  BrowserEntry(
    id: id,
    title: title,
    titleID: "PCSA00001",
    console: "PS Vita",
    consoleCode: "PSV",
    category: "Game",
    region: "US",
    fileSize: nil,
    packageURL: URL(string: "https://example.test/\(id).pkg"),
    sha256: nil,
    contentID: nil
  )
}
