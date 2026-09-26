import Foundation
import Testing
@testable import NPSCore

@Suite(.sourceEnglish)
struct LocalizationTests {
  @Test
  func packagesExactlyTheSupportedLanguageTags() {
    // Arrange
    let expected = Set(LocalizationCatalogAudit.expectedTags.map { $0.lowercased() })

    // Act
    let packaged = Localization.availableLocalizations()

    // Assert
    #expect(packaged.count == LocalizationCatalogAudit.expectedTags.count)
    #expect(Set(packaged.map { $0.lowercased() }) == expected)
    #expect(Localization.shared.availableLocalizations == packaged)
  }

  @Test
  func everyCatalogHasExactlyTheTemplateKeysAndPlaceholders() {
    // Arrange
    let templateKeys = Set(LocalizationCatalogAudit.templateStrings().keys)
    let templatePluralKeys = Set(LocalizationCatalogAudit.templatePlurals().keys)
    let templateSignatures = LocalizationCatalogAudit.templatePlaceholderSignatures()

    // Assert
    #expect(templateKeys.count > 100)
    #expect(
      templatePluralKeys == [
        "status.items", "downloads.count", "error.catalogue.columnCount",
        "error.download.byteCount",
      ]
    )
    #expect(templateKeys.isDisjoint(with: templatePluralKeys))
    for tag in LocalizationCatalogAudit.expectedTags {
      #expect(Set(LocalizationCatalogAudit.strings(for: tag).keys) == templateKeys, "\(tag)")
      #expect(Set(LocalizationCatalogAudit.plurals(for: tag).keys) == templatePluralKeys, "\(tag)")
      #expect(
        LocalizationCatalogAudit.placeholderSignatures(for: tag) == templateSignatures,
        "\(tag) placeholders differ from the template"
      )
    }
  }

  @Test
  func catalogValuesAvoidASCIIQuotesAndThreeDotEllipses() {
    for tag in LocalizationCatalogAudit.expectedTags {
      for (key, value) in LocalizationCatalogAudit.strings(for: tag) {
        #expect(!value.contains("\\\""), "\(tag) \(key) uses an ASCII double quote")
        #expect(!value.contains("..."), "\(tag) \(key) uses ... instead of …")
      }
    }
  }

  @Test
  func pluralEntriesUseTheCategoriesFoundationSelectsForEachLanguage() throws {
    for tag in LocalizationCatalogAudit.expectedTags {
      // Arrange
      let expected = try LocalizationCatalogAudit.foundationPluralCategories(for: tag)

      // Act
      let categories = LocalizationCatalogAudit.pluralCategories(for: tag)

      // Assert
      #expect(!categories.isEmpty, "\(tag) has no plurals")
      for (key, found) in categories {
        #expect(found == expected, "\(tag) \(key): \(found.sorted()) vs \(expected.sorted())")
      }
    }
  }

  @Test
  func nonEnglishCatalogsTranslateSourceEnglishProse() {
    for tag in LocalizationCatalogAudit.expectedTags where !LocalizationCatalogAudit.isEnglish(tag)
    {
      let untranslated = LocalizationCatalogAudit.sourceIdenticalEnglishProseKeys(for: tag)
        .subtracting(LocalizationCatalogAudit.allowedSourceIdenticalKeys(for: tag))
      #expect(untranslated.isEmpty, "\(tag) leaves source English in \(untranslated.sorted())")
    }
  }

  @Test
  func englishSourceCatalogsFollowTheirSpellingRules() {
    // Arrange
    let american = Localization(preferredLanguages: ["en-US"])
    let posix = Localization(preferredLanguages: ["C"])
    let british = Localization(preferredLanguages: ["en-GB"])

    // Assert
    #expect(american.string("action.reload") == "Reload Catalog")
    #expect(american.string("status.loading") == "Loading catalog…")
    #expect(posix.string("action.reload") == "Reload Catalog")
    #expect(british.string("action.reload") == "Reload Catalogue")
    #expect(british.string("status.loading") == "Loading catalogue…")
    #expect(
      LocalizationCatalogAudit.strings(for: "C") == LocalizationCatalogAudit.templateStrings()
    )
    #expect(
      LocalizationCatalogAudit.strings(for: "en-US") == LocalizationCatalogAudit.templateStrings()
    )
  }

  @Test
  func britishCatalogUsesBritishSpellings() throws {
    // Arrange
    let british = Localization(preferredLanguages: ["en-GB"])
    let american = try NSRegularExpression(
      pattern: #"\b(license|catalogs?|colors?|centers?|behaviors?|canceled|favorites?)\b"#,
      options: [.caseInsensitive]
    )

    // Act
    let flagged = LocalizationCatalogAudit.strings(for: "en-GB").filter { _, value in
      american.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    // Assert
    #expect(british.string("settings.createLicense") == "Create RAP licence files")
    #expect(british.string("error.download.invalidRAPPayload").contains("RAP licence file"))
    #expect(flagged.isEmpty, "American spellings in en-GB: \(flagged.keys.sorted())")
  }

  @Test(arguments: [
    (["zh-Hans-CN"], "zh-CN"), (["zh-Hant-TW"], "zh-TW"), (["zh-HK"], "zh-TW"), (["nb"], "nb-NO"),
    (["no"], "nb-NO"), (["pt-BR"], "pt-BR"), (["pt"], "pt-BR"), (["pt-PT"], "pt-PT"),
    (["en-AU"], "en-GB"), (["en"], "en-US"), (["de-AT"], "de-DE"), (["es-MX"], "es-ES"),
    (["xx"], "en-US"), (["xx", "ja-JP"], "ja-JP"),
  ])
  func preferredLanguagesResolveToAPackagedTag(preferences: [String], expected: String) {
    // Act
    let resolver = Localization(preferredLanguages: preferences)

    // Assert
    #expect(resolver.resolvedLanguage?.lowercased() == expected.lowercased())
  }

  @Test
  func preferredLanguageSelectionUsesTheLocaleCatalog() {
    // Arrange
    let resolver = Localization(preferredLanguages: ["zh-Hans-CN", "en-US"])

    // Act
    let value = resolver.string("section.all")
    let missing = resolver.string("test.missing.key", defaultValue: "Source fallback")

    // Assert
    #expect(value == "全部内容")
    #expect(missing == "Source fallback")
  }

  @Test
  func pluralsFormatTheCountForTheResolvedLanguage() {
    // Arrange
    let american = Localization(preferredLanguages: ["en-US"])
    let posix = Localization(preferredLanguages: ["C"])
    let chinese = Localization(preferredLanguages: ["zh-CN"])

    // Assert
    #expect(american.plural("status.items", count: 36_432) == "36,432 items")
    #expect(american.plural("status.items", count: 1) == "1 item")
    #expect(american.plural("status.items", count: 0) == "0 items")
    #expect(american.plural("downloads.count", count: 1) == "1 download")
    #expect(american.plural("downloads.count", count: 2) == "2 downloads")
    #expect(posix.plural("downloads.count", count: 1) == "1 download")
    #expect(chinese.plural("downloads.count", count: 3) == "3 个下载")
  }

  @Test
  func formattedValuesSubstituteCatalogPlaceholders() {
    // Arrange
    let resolver = Localization(preferredLanguages: ["en-US"])

    // Act
    let value = resolver.formatted("downloads.progress.label", arguments: ["Wipeout" as CVarArg])

    // Assert
    #expect(value == "Download progress for Wipeout")
  }

  @Test
  func formattedNumbersFollowTheResolvedLanguageNotTheSystemLocale() {
    // Arrange
    let american = Localization(preferredLanguages: ["en-US"])
    let german = Localization(preferredLanguages: ["de-DE"])
    let arguments: [CVarArg] = [1_234_567, "SHA256"]

    // Act
    let americanValue = american.formatted("error.catalogue.missingField", arguments: arguments)
    let germanValue = german.formatted("error.catalogue.missingField", arguments: arguments)

    // Assert
    #expect(german.resolvedLanguage?.lowercased() == "de-de")
    #expect(americanValue.contains("row 1,234,567 is missing"))
    #expect(germanValue.contains("1.234.567"))
  }
}
