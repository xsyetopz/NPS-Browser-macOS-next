import Foundation
import Testing
@testable import NPSCore

extension CatalogParserTests {
  @Test
  func parsesPackAndPatchFeedsIntoThePersistedCompatibilityKinds() throws {
    let packs = try CatalogParser.parseCompatibilityPacks(
      "PCSB01101/PCSB01101-03_650-01_00-01_00.ppk=Accel World vs. Sword Art Online\r\n",
      kind: .pack
    )
    let patches = try CatalogParser.parseCompatibilityPacks(
      "patch/PCSB01101/PCSB01101-03_650-02_03-01_00.ppk=Accel World vs. Sword Art Online Patch",
      kind: .patch
    )

    #expect(packs.count == 1)
    #expect(packs[0].titleID == "PCSB01101")
    #expect(packs[0].kind == .pack)
    #expect(packs[0].kind.fileType == .CPack)
    #expect(packs[0].displayName == "Accel World vs. Sword Art Online")
    #expect(
      packs[0].downloadURL.absoluteString
        == "https://gitlab.com/nopaystation_repos/nps_compati_packs/raw/master/PCSB01101/PCSB01101-03_650-01_00-01_00.ppk"
    )
    #expect(patches.count == 1)
    #expect(patches[0].kind == .patch)
    #expect(patches[0].kind.fileType == .CPatch)
    #expect(patches[0].downloadURL.path.contains("/patch/PCSB01101/"))
  }

  @Test(arguments: [
    "../PCSB01101/game.ppk=Traversal", "PCSB01101/..=Traversal",
    "PCSB01101/game.zip=Wrong extension", "PCSB0001/game.ppk=Invalid title ID",
  ])
  func rejectsInvalidCompatibilityFeedPaths(line: String) {
    #expect(throws: CatalogParseError.self) {
      try CatalogParser.parseCompatibilityPacks(line, kind: .pack)
    }
  }
}
