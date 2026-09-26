import Foundation

/// Resolves packaged `Localizable` strings and plurals for every NPS Browser target.
///
/// NPSCore owns the resource bundle so the app and libraries share one catalog.
public struct Localization: @unchecked Sendable {
  public static let sourceLocalization = "en-US"

  /// Resolver for the user's preferred languages. Code that renders text uses
  /// `current`, which a task can override (tests pin source English).
  public static let shared = Self(preferredLanguages: ambientPreferredLanguages())

  /// SwiftPM resource bundle. Tests pin this instead of `Bundle.main`.
  public static var moduleBundle: Bundle { .module }

  private let localizationNames: [String]
  private let localizedLanguage: String?
  private let preferredBundle: Bundle?
  private let sourceEnglishBundle: Bundle?
  private let isSourceLanguage: Bool
  private let formattingLocale: Locale

  public init(bundle: Bundle? = nil, preferredLanguages: [String] = Locale.preferredLanguages) {
    let bundle = bundle ?? Self.moduleBundle
    let localizationNames = Self.availableLocalizations(in: bundle)
    let localizedLanguage = Self.localizedLanguage(
      among: localizationNames,
      preferredLanguages: preferredLanguages
    )
    self.localizationNames = localizationNames
    self.localizedLanguage = localizedLanguage
    self.preferredBundle = Self.localizedBundle(for: localizedLanguage, in: bundle)
    self.sourceEnglishBundle = Self.sourceEnglishBundle(among: localizationNames, in: bundle)
    self.isSourceLanguage =
      localizedLanguage?.caseInsensitiveCompare(Self.sourceLocalization) == .orderedSame
    self.formattingLocale = Self.formattingLocale(for: localizedLanguage)
  }

  /// Best packaged translation for `key`, then `defaultValue`, then the key.
  public func string(_ key: String, defaultValue: String? = nil, comment: String = "") -> String {
    let fallback = defaultValue ?? key
    guard let preferredBundle else { return fallback }

    let value = NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: preferredBundle,
      value: fallback,
      comment: comment
    )
    guard value == fallback, !isSourceLanguage else { return value }

    // Incomplete locale: prefer source English over a raw key.
    guard let sourceBundle = sourceEnglishBundle, sourceBundle !== preferredBundle else {
      return value
    }
    return NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: sourceBundle,
      value: fallback,
      comment: comment
    )
  }

  /// Formats `count` through a `Localizable.stringsdict` plural (`%#@count@`).
  /// Foundation picks the CLDR category; callers should not branch on `count == 1`.
  public func plural(
    _ key: String,
    count: Int,
    defaultValue: String? = nil,
    comment: String = ""
  ) -> String {
    let fallback = defaultValue ?? key
    guard let preferredBundle else {
      return Self.format(fallback, count: count, locale: formattingLocale)
    }

    let value = NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: preferredBundle,
      value: fallback,
      comment: comment
    )
    guard value == fallback, !isSourceLanguage else {
      return Self.format(value, count: count, locale: formattingLocale)
    }

    // Incomplete locale: format source English, not a raw `%#@count@` string.
    guard let sourceBundle = sourceEnglishBundle else {
      return Self.format(value, count: count, locale: formattingLocale)
    }
    let sourceValue = NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: sourceBundle,
      value: fallback,
      comment: comment
    )
    return Self.format(sourceValue, count: count, locale: formattingLocale)
  }

  /// Formats with the resolved language's locale (as plurals do) unless `locale` is given.
  /// Placeholder types stay those in the source catalog.
  public func formatted(
    _ key: String,
    defaultValue: String? = nil,
    locale: Locale? = nil,
    arguments: [CVarArg]
  ) -> String {
    String(
      format: string(key, defaultValue: defaultValue),
      locale: locale ?? formattingLocale,
      arguments: arguments
    )
  }

  /// The localization selected for the injected preference order, if any.
  public var resolvedLanguage: String? { localizedLanguage }

  /// All locale directories that SwiftPM packaged for this resource bundle.
  public var availableLocalizations: [String] { localizationNames }

  /// Returns locale directories present in a bundle, excluding Base resources.
  public static func availableLocalizations(in bundle: Bundle? = nil) -> [String] {
    let bundle = bundle ?? moduleBundle
    if let resourceURL = bundle.resourceURL,
      let entries = try? FileManager.default.contentsOfDirectory(
        at: resourceURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    {
      let directories = entries.compactMap { url -> String? in
        guard url.pathExtension == "lproj" else { return nil }
        return url.deletingPathExtension().lastPathComponent
      }
      if !directories.isEmpty { return directories.sorted() }
    }
    return bundle.localizations.filter { $0.caseInsensitiveCompare("Base") != .orderedSame }
      .sorted()
  }

  private static func localizedLanguage(
    among localizations: [String],
    preferredLanguages: [String]
  ) -> String? {
    guard
      let preferred = Bundle.preferredLocalizations(
        from: localizations,
        forPreferences: preferredLanguages
      ).first
    else { return nil }
    return localizations.first { $0.caseInsensitiveCompare(preferred) == .orderedSame }
  }

  private static func localizedBundle(for language: String?, in bundle: Bundle) -> Bundle? {
    guard let language, let path = bundle.path(forResource: language, ofType: "lproj") else {
      return nil
    }
    return Bundle(path: path)
  }

  /// SwiftPM's native build lowercases `.lproj` names, so match them case-insensitively.
  private static func sourceEnglishBundle(
    among localizations: [String],
    in bundle: Bundle
  ) -> Bundle? {
    for language in [Self.sourceLocalization, "en", "C"] {
      guard
        let directory = localizations.first(where: {
          $0.caseInsensitiveCompare(language) == .orderedSame
        }), let candidate = localizedBundle(for: directory, in: bundle)
      else { continue }
      return candidate
    }
    return nil
  }

  private static func formattingLocale(for language: String?) -> Locale {
    guard let language else { return .current }
    // `C` is the POSIX source catalog: English text needs English plural rules.
    if language.caseInsensitiveCompare("C") == .orderedSame {
      return Locale(identifier: "en_US_POSIX")
    }
    return Locale(identifier: language.replacingOccurrences(of: "-", with: "_"))
  }

  private static func format(_ value: String, count: Int, locale: Locale) -> String {
    String(format: value, locale: locale, arguments: [count])
  }
}
