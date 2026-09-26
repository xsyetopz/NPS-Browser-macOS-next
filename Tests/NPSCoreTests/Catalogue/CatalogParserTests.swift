import Foundation
import Testing
@testable import NPSCore

private let psvGameHeader =
  "Title ID\tRegion\tName\tPKG direct link\tzRIF\tContent ID\tLast Modification Date\t"
  + "Original Name\tFile Size\tSHA256\tRequired FW"
private let ps3GameHeader =
  "Title ID\tRegion\tName\tPKG direct link\tRAP\tContent ID\tLast Modification Date\t"
  + "Download .RAP file\tFile Size\tSHA256"
private let psmGameHeader =
  "Title ID\tRegion\tName\tPKG direct link\tzRIF\tContent ID\tLast Modification Date\t"
  + "File Size\tSHA256"
private let pspDLCHeader =
  "Title ID\tRegion\tName\tPKG direct link\tContent ID\tLast Modification Date\tRAP\t"
  + "Download .RAP file\tFile Size\tSHA256"

@Suite(.sourceEnglish)
struct CatalogParserTests {
  @Test
  func parsesPSVGameAndMapsLegacyColumns() throws {
    let hash = String(repeating: "a", count: 64)
    let tsv =
      psvGameHeader + "\n"
      + "PCSA00001\tUS\tExample Game\thttps://cdn.example/game.pkg\tlicense\tUP0000-PCSA00001_00-GAME000000000000\t2024-05-06 07:08:09\tExample.pkg\t1024\t\(hash)\t3.60\n"

    let rows = try CatalogParser.parseTSV(tsv, kind: CatalogKind(console: .PSV, fileType: .Game))

    #expect(rows.count == 1)
    #expect(rows[0].titleID == "PCSA00001")
    #expect(rows[0].fileSize == 1024)
    #expect(rows[0].requiredFirmware == 3.6)
    #expect(rows[0].sha256 == hash)
    #expect(rows[0].legacyPrimaryKey == "USGamePCSA00001UP0000-PCSA00001_00-GAME000000000000")
  }

  @Test
  func parsesPSMGameNineColumnFeedWithoutShiftingFields() throws {
    let hash = String(repeating: "b", count: 64)
    let tsv =
      psmGameHeader + "\n"
      + "NPUG10001\tUS\tBeats, Advanced\thttps://cdn.example/psm.pkg\tzrif-value\tUP0001-NPUG10001_00-PSMGAME000000000\t2016-11-05 12:13:14\t7340032\t\(hash)"

    let item = try #require(
      CatalogParser.parseTSV(tsv, kind: CatalogKind(console: .PSM, fileType: .Game)).first
    )

    #expect(item.consoleType == .PSM)
    #expect(item.fileType == .Game)
    #expect(item.titleID == "NPUG10001")
    #expect(item.name == "Beats, Advanced")
    #expect(item.packageURL == URL(string: "https://cdn.example/psm.pkg"))
    #expect(item.zrif == "zrif-value")
    #expect(item.contentID == "UP0001-NPUG10001_00-PSMGAME000000000")
    #expect(item.fileSize == 7340032)
    #expect(item.sha256 == hash)
  }

  @Test
  func parsesPSPDLCWithTenColumnRAPAndPackageFields() throws {
    let hash = String(repeating: "c", count: 64)
    let tsv =
      pspDLCHeader + "\n"
      + "NPJH90123\tJP\tExample PSP add-on\thttps://cdn.example/psp-dlc.pkg\tUP0001-NPJH90123_00-ADDON00000000000\t2015-03-04 05:06:07\t0123456789abcdef0123456789abcdef\thttps://cdn.example/license.rap\t4096\t\(hash)"

    let item = try #require(
      CatalogParser.parseTSV(tsv, kind: CatalogKind(console: .PSP, fileType: .DLC)).first
    )

    #expect(item.consoleType == .PSP)
    #expect(item.fileType == .DLC)
    #expect(item.titleID == "NPJH90123")
    #expect(item.name == "Example PSP add-on")
    #expect(item.packageURL == URL(string: "https://cdn.example/psp-dlc.pkg"))
    #expect(item.contentID == "UP0001-NPJH90123_00-ADDON00000000000")
    #expect(item.rap == "0123456789abcdef0123456789abcdef")
    #expect(item.rapDownloadURL == URL(string: "https://cdn.example/license.rap"))
    #expect(item.fileSize == 4096)
    #expect(item.sha256 == hash)
  }

  @Test
  func rejectsShortRowsInsteadOfIndexingPastEnd() {
    let tsv = psvGameHeader + "\nPCSA00001\tUS\ttoo short"
    do {
      _ = try CatalogParser.parseTSV(tsv, kind: CatalogKind(console: .PSV, fileType: .Game))
      Issue.record("Expected the short row to fail.")
    } catch let error as CatalogParseError {
      #expect(error == .wrongColumnCount(row: 2, expectedAtLeast: 11, found: 3))
    } catch { Issue.record("Unexpected error: \(error)") }
  }

  @Test(arguments: ["<html>503 Service Unavailable</html>", "upstream error"])
  func rejectsErrorPagesAndArbitraryHeadersInsteadOfReturningAnEmptyCatalogue(body: String) {
    #expect(throws: CatalogParseError.invalidHeader(CatalogKind(console: .PSV, fileType: .Game))) {
      try CatalogParser.parseTSV(body, kind: CatalogKind(console: .PSV, fileType: .Game))
    }
  }

  @Test
  func rejectsAValidHeaderWithoutRowsInsteadOfReturningAnEmptyCatalogue() {
    #expect(throws: CatalogParseError.emptyCatalogue) {
      try CatalogParser.parseTSV(psvGameHeader, kind: CatalogKind(console: .PSV, fileType: .Game))
    }
  }

  @Test
  func rejectsInvalidHashAndUnsafePackageScheme() {
    let fields = [
      "PCSA00001", "US", "Example", "file:///etc/passwd", "license", "CID", "2024-05-06 07:08:09",
      "Example.pkg", "1024", "not-a-hash", "3.60",
    ]
    let tsv = psvGameHeader + "\n" + fields.joined(separator: "\t")
    do {
      _ = try CatalogParser.parseTSV(tsv, kind: CatalogKind(console: .PSV, fileType: .Game))
      Issue.record("Expected a non-HTTP URL to fail.")
    } catch let error as CatalogParseError {
      #expect(error == .invalidField(row: 2, field: "pkgDirectLink", value: "file:///etc/passwd"))
    } catch { Issue.record("Unexpected error: \(error)") }

    let invalidHash = fields.enumerated().map { index, value in
      index == 3 ? "https://cdn.example/file.pkg" : value
    }
    do {
      _ = try CatalogParser.parseTSV(
        psvGameHeader + "\n" + invalidHash.joined(separator: "\t"),
        kind: CatalogKind(console: .PSV, fileType: .Game)
      )
      Issue.record("Expected an invalid SHA-256 to fail.")
    } catch let error as CatalogParseError {
      #expect(error == .invalidField(row: 2, field: "sha256", value: "not-a-hash"))
    } catch { Issue.record("Unexpected error: \(error)") }
  }

  @Test(arguments: ["MISSING", "CART ONLY", "NOT REQUIRED"])
  func mapsPublishedNonDownloadMarkersToNoURL(marker: String) throws {
    let tsv =
      psvGameHeader
      + "\nPCSA00099\tUS\tTearaway\t\(marker)\tlicense\tUP9000-PCSA00099_00-TEARAWAY00000000\t"
      + "2017-10-19 04:55:13\tTearaway\t\t\t1"

    let row = try #require(
      CatalogParser.parseTSV(tsv, kind: CatalogKind(console: .PSV, fileType: .Game)).first
    )

    #expect(row.packageURL == nil)
    #expect(row.fileSize == nil)
    #expect(row.sha256 == nil)
  }

  @Test
  func leavesFractionalUnitlessCatalogueSizesUnavailable() throws {
    let hash = String(repeating: "0", count: 64)
    let tsv =
      ps3GameHeader
      + "\nNPUD21152\tUS\tDigital Devil Saga 2\thttps://cdn.example/game.pkg\tRAP\tCONTENT\t2021-04-24 00:30:35\tignored\t4.7\t\(hash)"

    let item = try #require(
      CatalogParser.parseTSV(tsv, kind: CatalogKind(console: .PS3, fileType: .Game)).first
    )

    #expect(item.fileSize == nil)
  }

  @Test
  func constructsThePRRAPRouteAndEscapesPathComponents() throws {
    let hash = String(repeating: "0", count: 64)
    let tsv =
      ps3GameHeader
      + "\nTITLE\tUS\tGame\thttps://cdn.example/game.pkg\tAB/CD\tCONTENT?ID\t2024-01-02 03:04:05\tignored\t2048\t\(hash)"

    let item = try #require(
      CatalogParser.parseTSV(tsv, kind: CatalogKind(console: .PS3, fileType: .Game)).first
    )
    let rapURL = try #require(item.rapDownloadURL)

    #expect(rapURL.absoluteString == "https://nopaystation.com/tools/rap2file/CONTENT%3FID/AB%2FCD")
  }

  @Test
  func treatsTheUnlockLicenseByDLCMarkerAsUnavailableRAP() throws {
    let hash = String(repeating: "0", count: 64)
    let tsv =
      ps3GameHeader + "\nNPUD21152\tUS\tDigital Devil Saga 2\tN/A\tUNLOCK/LICENSE BY DLC\t"
      + "UP0001-NPUD21152_00-GAME000000000000\t2021-04-24 00:30:35\tignored\t2048\t\(hash)"

    let item = try #require(
      CatalogParser.parseTSV(tsv, kind: CatalogKind(console: .PS3, fileType: .Game)).first
    )

    #expect(item.rap == nil)
    #expect(item.rapDownloadURL == nil)
  }
}
