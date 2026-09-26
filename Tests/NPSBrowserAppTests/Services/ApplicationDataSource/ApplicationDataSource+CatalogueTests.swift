import Foundation
import NPSCore
import NPSBrowserAppResources
import Testing
@testable import NPSBrowserApp

@Test(.sourceEnglish)
func PSMAndPSPDLCDefaultsAreMappedIntoFilterableCatalogueEntries() throws {
  let kinds = Dictionary(uniqueKeysWithValues: ApplicationDataSource.supportedSources)
  #expect(kinds[.psmGames] == CatalogKind(console: .PSM, fileType: .Game))
  #expect(kinds[.pspDLCs] == CatalogKind(console: .PSP, fileType: .DLC))
  #expect(CatalogSource.allCases.contains(.psmGames))
  #expect(CatalogSource.allCases.contains(.pspDLCs))

  let hash = String(repeating: "d", count: 64)
  let psmTSV = """
    Title ID\tRegion\tName\tPKG direct link\tzRIF\tContent ID\tLast Modification Date\tFile Size\
    \tSHA256
    NPUG10002\tEU\tPSM Fixture Game\thttps://cdn.example/psm-fixture.pkg\tfixture-zrif\tUP0001-NPUG10002_00-FIXTURE000000000\t2016-11-05 12:13:14\t8192\t\(hash)
    """
  let pspDLCTSV = """
    Title ID\tRegion\tName\tPKG direct link\tContent ID\tLast Modification Date\tRAP\
    \tDownload .RAP file\tFile Size\tSHA256
    NPJH90124\tJP\tPSP Fixture Add-on\thttps://cdn.example/psp-addon.pkg\tUP0001-NPJH90124_00-FIXTURE000000000\t2015-03-04 05:06:07\t0123456789abcdef0123456789abcdef\thttps://cdn.example/psp-addon.rap\t2048\t\(hash)
    """
  let psmItem = try #require(CatalogParser.parseTSV(psmTSV, kind: kinds[.psmGames]!).first)
  let pspDLCItem = try #require(CatalogParser.parseTSV(pspDLCTSV, kind: kinds[.pspDLCs]!).first)
  let psmEntry = BrowserEntry(item: psmItem)
  let pspDLCEntry = BrowserEntry(item: pspDLCItem)

  #expect(psmEntry.consoleCode == ConsoleType.PSM.rawValue)
  #expect(psmEntry.console == AppResources.localized("section.psm"))
  #expect(pspDLCEntry.consoleCode == ConsoleType.PSP.rawValue)
  #expect(pspDLCEntry.category == FileType.DLC.rawValue)
  #expect(pspDLCEntry.supportsPackageDownload)
  #expect(pspDLCItem.rapDownloadURL == URL(string: "https://cdn.example/psp-addon.rap"))
  #expect(
    CatalogFilter.matching([psmEntry, pspDLCEntry], section: .psm, bookmarkedIDs: [], query: "")
      .map(\.id) == [psmEntry.id]
  )
  #expect(
    CatalogFilter.matching([psmEntry, pspDLCEntry], section: .psp, bookmarkedIDs: [], query: "")
      .map(\.id) == [pspDLCEntry.id]
  )
}
