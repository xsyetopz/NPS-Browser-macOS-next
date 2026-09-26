import Foundation
import Testing
@testable import NPSCore

/// Reads the packaged catalogs directly so tests can compare their shape.
enum LocalizationCatalogAudit {
  /// The 20 PS3 system languages plus the POSIX `C` source catalog.
  static let expectedTags = [
    "C", "en-US", "en-GB", "da-DK", "de-DE", "es-ES", "fr-FR", "it-IT", "nl-NL", "nb-NO", "pt-BR",
    "pt-PT", "ru-RU", "fi-FI", "pl-PL", "sv-SE", "tr-TR", "ja-JP", "ko-KR", "zh-CN", "zh-TW",
  ]

  /// Brand and technical tokens that stay in English in every language, longest first.
  static let untranslatedTokens = [
    "PlayStation Portable", "PlayStation Mobile", "PlayStation Vita", "PlayStation", "NPS Browser",
    "PS Vita", "HTTPS", "HTTP", "zRIF", "PKG", "RAP", "URL", "ZIP", "ISO", "PSP", "PS3",
  ]

  /// Returns the packaged directory name for `tag`; SwiftPM may lowercase it.
  static func directory(for tag: String) -> String? {
    Localization.availableLocalizations().first { $0.caseInsensitiveCompare(tag) == .orderedSame }
  }

  static func isEnglish(_ localization: String) -> Bool {
    localization.caseInsensitiveCompare("C") == .orderedSame
      || localization.lowercased().hasPrefix("en-")
  }

  static func templateStrings() -> [String: String] {
    templateData(extension: "strings").map(parseStrings) ?? [:]
  }

  static func templatePlurals() -> [String: Any] {
    templateData(extension: "stringsdict").map(propertyList) ?? [:]
  }

  static func strings(for localization: String) -> [String: String] {
    resourceData(for: localization, extension: "strings").map(parseStrings) ?? [:]
  }

  static func plurals(for localization: String) -> [String: Any] {
    resourceData(for: localization, extension: "stringsdict").map(propertyList) ?? [:]
  }

  static func templatePlaceholderSignatures() -> [String: [String]] {
    placeholderSignatures(strings: templateStrings(), plurals: templatePlurals())
  }

  static func placeholderSignatures(for localization: String) -> [String: [String]] {
    placeholderSignatures(strings: strings(for: localization), plurals: plurals(for: localization))
  }

  static func pluralCategories(for localization: String) -> [String: Set<String>] {
    plurals(for: localization).mapValues(collectPluralCategories)
  }

  /// Keys whose value is identical to source English and still reads as English prose.
  static func sourceIdenticalEnglishProseKeys(for localization: String) -> Set<String> {
    let sourceStrings = templateStrings()
    var result = Set(
      strings(for: localization).compactMap { key, value in
        sourceStrings[key] == value && isEnglishProse(value) ? key : nil
      }
    )
    let sourcePlurals = templatePlurals()
    for (key, localizedValue) in plurals(for: localization) {
      guard let sourceValue = sourcePlurals[key] else { continue }
      var sourceValues: [String] = []
      var localizedValues: [String] = []
      collectPluralStrings(sourceValue, into: &sourceValues)
      collectPluralStrings(localizedValue, into: &localizedValues)
      if localizedValues.contains(where: { sourceValues.contains($0) && isEnglishProse($0) }) {
        result.insert(key)
      }
    }
    return result
  }

  static func placeholderSignature(in value: String) -> [String] {
    let pattern = #"%(?:#@\w+@|(?:[0-9]+\$)?[-+0-9.#]*[@a-zA-Z])"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    let placeholders = expression.matches(in: value, range: range).compactMap { match in
      Range(match.range, in: value).map { String(value[$0]) }
    }
    // Positional placeholders (`%2$@`) name their argument, so translations may
    // reorder them; only unnumbered placeholders must keep the source order.
    let isPositional = !placeholders.isEmpty && placeholders.allSatisfy { $0.contains("$") }
    return isPositional ? placeholders.sorted() : placeholders
  }

  static func isEnglishProse(_ value: String) -> Bool {
    var remainder = value.replacingOccurrences(
      of: #"%(?:#@\w+@|(?:[0-9]+\$)?[-+0-9.#]*[@a-zA-Z])|\S+://\S+"#,
      with: "",
      options: .regularExpression
    )
    for token in untranslatedTokens {
      remainder = remainder.replacingOccurrences(of: token, with: "")
    }
    return remainder.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil
  }

  /// The plural categories Foundation selects for integers in `localization`, plus the
  /// mandatory `other`. `C` is the English source, so it follows `en-US` rules.
  static func foundationPluralCategories(for localization: String) throws -> Set<String> {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSPluralProbe-\(UUID().uuidString).lproj"
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let categories = ["zero", "one", "two", "few", "many", "other"]
    let rule: [String: Any] = [
      "NSStringLocalizedFormatKey": "%#@count@",
      "count": categories.reduce(
        into: [
          "NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "d",
        ] as [String: Any]
      ) { rule, category in if category != "zero" { rule[category] = category } },
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: ["probe": rule],
      format: .xml,
      options: 0
    )
    try data.write(to: root.appendingPathComponent("Localizable.stringsdict"))
    let bundle = try #require(Bundle(url: root))
    let format = bundle.localizedString(forKey: "probe", value: nil, table: nil)
    let language = isEnglish(localization) ? Localization.sourceLocalization : localization
    let locale = Locale(identifier: language.replacingOccurrences(of: "-", with: "_"))
    var selected: Set<String> = ["other"]
    for count in Array(0...300) + [1_000, 1_000_000, 2_000_000, 1_000_001] {
      selected.insert(String(format: format, locale: locale, count))
    }
    return selected
  }

  private static func templateData(extension: String) -> Data? {
    guard
      let url = Localization.moduleBundle.url(
        forResource: "Localizable.template",
        withExtension: `extension`
      )
    else { return nil }
    return try? Data(contentsOf: url)
  }

  private static func resourceData(for localization: String, extension: String) -> Data? {
    guard let directory = directory(for: localization),
      let path = Localization.moduleBundle.path(
        forResource: "Localizable",
        ofType: `extension`,
        inDirectory: "\(directory).lproj"
      )
    else { return nil }
    return try? Data(contentsOf: URL(fileURLWithPath: path))
  }

  private static func propertyList(_ data: Data) -> [String: Any] {
    let value = try? PropertyListSerialization.propertyList(from: data, format: nil)
    return value as? [String: Any] ?? [:]
  }

  private static func parseStrings(_ data: Data) -> [String: String] {
    guard let text = String(data: data, encoding: .utf8) else { return [:] }
    let pattern = #""((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    var result: [String: String] = [:]
    expression.enumerateMatches(in: text, range: range) { match, _, _ in
      guard let match, let keyRange = Range(match.range(at: 1), in: text),
        let valueRange = Range(match.range(at: 2), in: text)
      else { return }
      result[String(text[keyRange])] = String(text[valueRange])
    }
    return result
  }

  private static func placeholderSignatures(
    strings: [String: String],
    plurals: [String: Any]
  ) -> [String: [String]] {
    var result = strings.mapValues { placeholderSignature(in: $0) }
    for (key, value) in plurals {
      var values: [String] = []
      collectPluralStrings(value, into: &values)
      if let format = (value as? [String: Any])?["NSStringLocalizedFormatKey"] as? String {
        values.append(format)
      }
      result[key] = Array(Set(values.flatMap { placeholderSignature(in: $0) })).sorted()
    }
    return result
  }

  private static func collectPluralStrings(_ value: Any, into strings: inout [String]) {
    if let string = value as? String {
      strings.append(string)
      return
    }
    guard let dictionary = value as? [String: Any] else { return }
    for (key, child) in dictionary.sorted(by: { $0.key < $1.key }) where !key.hasPrefix("NSString")
    { collectPluralStrings(child, into: &strings) }
  }

  private static func collectPluralCategories(_ value: Any) -> Set<String> {
    guard let dictionary = value as? [String: Any] else { return [] }
    if dictionary["NSStringFormatSpecTypeKey"] as? String == "NSStringPluralRuleType" {
      return Set(dictionary.keys.filter { !$0.hasPrefix("NSString") })
    }
    return dictionary.values.reduce(into: Set<String>()) { result, child in
      result.formUnion(collectPluralCategories(child))
    }
  }
}
