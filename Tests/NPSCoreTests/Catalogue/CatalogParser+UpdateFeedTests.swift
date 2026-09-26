import Foundation
import Testing
@testable import NPSCore

extension CatalogParserTests {
  @Test
  func readsTheLastUpdatePackageAndPrefersHybridURL() throws {
    let xml = """
      <updates>
        <tag name="1.00">
          <package url="https://cdn.example/old.pkg" />
          <package url="https://cdn.example/base.pkg"><hybrid_package url="https://cdn.example/hybrid.pkg" /></package>
        </tag>
      </updates>
      """

    #expect(
      try CatalogParser.parseUpdateXML(xml).absoluteString == "https://cdn.example/hybrid.pkg"
    )
  }

  @Test
  func constructsVitaUpdateURLFromTheKnownHMACVector() throws {
    let expectedDigest = "86d7c3b64d554b9639c5ad69aac20e16ea34c2f513d412f38329257f4ad15782"

    let url = try CatalogParser.updateXMLURL(for: "PCSA00007")

    #expect(
      url.absoluteString
        == "http://gs-sec.ww.np.dl.playstation.net/pl/np/PCSA00007/\(expectedDigest)/PCSA00007-ver.xml"
    )
    #expect(try CatalogParser.updateXMLURL(for: "pcsa00007") == url)
  }

  @Test
  func rejectsInvalidTitleIDsBeforeConstructingUpdateURLs() {
    #expect(throws: CatalogParseError.invalidTitleID("../PCSA00007")) {
      try CatalogParser.updateXMLURL(for: "../PCSA00007")
    }
  }

  @Test
  func fallsBackToDirectURLWhenHybridURLIsInvalid() throws {
    let xml = """
      <updates>
        <tag name="1.00">
          <package url="https://cdn.example/direct.pkg"><hybrid_package url="file:///invalid.pkg" /></package>
        </tag>
      </updates>
      """

    #expect(
      try CatalogParser.parseUpdateXML(xml).absoluteString == "https://cdn.example/direct.pkg"
    )
  }

  @Test
  func usesValidHybridURLWhenDirectURLIsInvalid() throws {
    let xml = """
      <updates>
        <tag name="1.00">
          <package url="javascript:alert(1)"><hybrid_package url="https://cdn.example/hybrid.pkg" /></package>
        </tag>
      </updates>
      """

    #expect(
      try CatalogParser.parseUpdateXML(xml).absoluteString == "https://cdn.example/hybrid.pkg"
    )
  }

  @Test
  func rejectsMalformedUpdateXMLAndMissingURL() {
    #expect(throws: CatalogParseError.self) { try CatalogParser.parseUpdateXML("<updates><tag>") }
    #expect(throws: CatalogParseError.missingUpdateURL) {
      try CatalogParser.parseUpdateXML(
        "<updates><tag><package url=\"file:///tmp/bad.pkg\" /></tag></updates>"
      )
    }
  }
}
