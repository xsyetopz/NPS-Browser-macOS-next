import Foundation
import Testing
@testable import NPSCore

@Suite(.sourceEnglish)
struct CatalogParseErrorTests {
  @Test
  func equalityDoesNotDependOnTheUILanguage() {
    // Arrange
    func parseFailure() -> CatalogParseError? {
      do {
        _ = try CatalogParser.parseCompatibilityPacks("no separator here", kind: .pack)
        return nil
      } catch { return error as? CatalogParseError }
    }
    let chinese = Localization(preferredLanguages: ["zh-CN"])

    // Act
    let english = parseFailure()
    let translated = Localization.$override.withValue(chinese) { parseFailure() }
    let chineseText = Localization.$override.withValue(chinese) { translated?.localizedDescription }

    // Assert
    #expect(english == .invalidCompatibilityEntry(row: 1, reason: .missingSeparator))
    #expect(english == translated)
    #expect(
      english?.localizedDescription == "Compatibility-feed row 1 is invalid: missing separator"
    )
    #expect(chineseText == "兼容性源第 1 行无效：缺少分隔符")
  }

  @Test
  func feedKindsAreNamedWithLocalizedTitlesNotRawValues() {
    // Arrange
    let header = CatalogParseError.invalidHeader(CatalogKind(console: .PSV, fileType: .DLC))
    let unsupported = CatalogParseError.unsupportedKind(
      CatalogKind(console: .PSM, fileType: .Theme)
    )
    let chinese = Localization(preferredLanguages: ["zh-CN"])

    // Act
    let english = header.localizedDescription
    let translated = Localization.$override.withValue(chinese) { header.localizedDescription }
    let unsupportedText = unsupported.localizedDescription

    // Assert
    #expect(
      english
        == "The catalog header does not match the expected PlayStation Vita Add-ons feed format."
    )
    #expect(translated == "目录表头与预期的 PlayStation Vita 附加内容源格式不符。")
    #expect(unsupportedText == "The catalog format is not supported for PlayStation Mobile Themes.")
  }

  @Test
  func everyCompatibilityIssueNamesACatalogKey() {
    // Act
    let texts = CompatibilityEntryIssue.allCases.map { $0.localizedMessage.resolved() }

    // Assert
    #expect(texts.allSatisfy { !$0.hasPrefix("error.catalogue.") })
    #expect(Set(texts).count == CompatibilityEntryIssue.allCases.count)
  }
}
