import CryptoKit
import Foundation

extension CatalogParser {
  /// Extracts the latest package URL from an NPS update-feed XML document.
  public static func parseUpdateXML(_ xml: String) throws -> URL {
    guard !xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CatalogParseError.emptyInput
    }
    let delegate = UpdateXMLDelegate()
    let parser = XMLParser(data: Data(xml.utf8))
    parser.delegate = delegate
    parser.shouldResolveExternalEntities = false
    guard parser.parse() else {
      throw CatalogParseError.malformedXML(parser.parserError?.localizedDescription)
    }
    guard let url = delegate.latestURL else { throw CatalogParseError.missingUpdateURL }
    return url
  }

  /// Builds the signed Vita update-feed URL without launching the legacy helper executable.
  public static func updateXMLURL(for titleID: String) throws -> URL {
    let normalizedTitleID = titleID.uppercased()
    guard isValidTitleID(normalizedTitleID) else { throw CatalogParseError.invalidTitleID(titleID) }
    let key = SymmetricKey(
      data: Data([
        0xE5, 0xE2, 0x78, 0xAA, 0x1E, 0xE3, 0x40, 0x82, 0xA0, 0x88, 0x27, 0x9C, 0x83, 0xF9, 0xBB,
        0xC8, 0x06, 0x82, 0x1C, 0x52, 0xF2, 0xAB, 0x5D, 0x2B, 0x4A, 0xBD, 0x99, 0x54, 0x50, 0x35,
        0x51, 0x14,
      ])
    )
    let message = Data("np_\(normalizedTitleID)".utf8)
    let digest = HMAC<SHA256>.authenticationCode(for: message, using: key).map {
      String(format: "%02x", $0)
    }.joined()

    var components = URLComponents()
    components.scheme = "http"
    components.host = "gs-sec.ww.np.dl.playstation.net"
    components.percentEncodedPath =
      "/pl/np/\(normalizedTitleID)/\(digest)/\(normalizedTitleID)-ver.xml"
    guard let url = components.url else { throw CatalogParseError.invalidTitleID(titleID) }
    return url
  }
}

private final class UpdateXMLDelegate: NSObject, XMLParserDelegate {
  private var depth = 0
  private var rootDepth: Int?
  private var tagDepth: Int?
  private var candidateDepth: Int?
  private var directCandidateURL: String?
  private var hybridCandidateURL: String?
  private var candidates: [URL] = []

  var latestURL: URL? { candidates.last }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    let parentDepth = depth
    depth += 1
    if rootDepth == nil {
      rootDepth = depth
      return
    }
    if tagDepth == nil, elementName == "tag", parentDepth == rootDepth {
      tagDepth = depth
      return
    }
    if let tagDepth, candidateDepth == nil, parentDepth == tagDepth {
      candidateDepth = depth
      directCandidateURL = attributeDict["url"]
      hybridCandidateURL = nil
      return
    }
    if let candidateDepth, depth > candidateDepth, elementName == "hybrid_package" {
      hybridCandidateURL = attributeDict["url"]
    }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    if let candidateDepth, depth == candidateDepth {
      let url = Self.validPackageURL(hybridCandidateURL) ?? Self.validPackageURL(directCandidateURL)
      if let url { candidates.append(url) }
      self.candidateDepth = nil
      directCandidateURL = nil
      hybridCandidateURL = nil
    }
    if let tagDepth, depth == tagDepth { self.tagDepth = nil }
    depth -= 1
  }

  private static func validPackageURL(_ rawValue: String?) -> URL? {
    guard let rawValue else { return nil }
    let candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty, url.user == nil,
      url.password == nil
    else { return nil }
    return url
  }
}
