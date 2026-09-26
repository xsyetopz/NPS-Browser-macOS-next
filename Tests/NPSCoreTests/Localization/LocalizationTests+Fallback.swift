import Foundation
import Testing
@testable import NPSCore

@Suite(.sourceEnglish)
struct LocalizationFallbackTests {
  @Test
  func incompleteLocaleFallsBackToSourceEnglishResource() throws {
    // Arrange
    let root = try makeBundle(localizations: ["en-US", "fr-FR"])
    defer { try? FileManager.default.removeItem(at: root) }
    let resources = root.appendingPathComponent("Contents/Resources")
    try Data("\"shared\" = \"English source\";\n".utf8).write(
      to: resources.appendingPathComponent("en-US.lproj/Localizable.strings")
    )
    try Data("\"frOnly\" = \"French value\";\n".utf8).write(
      to: resources.appendingPathComponent("fr-FR.lproj/Localizable.strings")
    )
    let bundle = try #require(Bundle(path: root.path))

    // Act
    let resolver = Localization(bundle: bundle, preferredLanguages: ["fr-FR"])

    // Assert
    #expect(resolver.resolvedLanguage == "fr-FR")
    #expect(resolver.string("frOnly", defaultValue: "Caller fallback") == "French value")
    #expect(resolver.string("shared", defaultValue: "Caller fallback") == "English source")
    #expect(resolver.string("missing", defaultValue: "Caller fallback") == "Caller fallback")
  }

  @Test
  func lowercasedPackagedTagsStillFindTheSourceEnglishCatalog() throws {
    // Arrange: SwiftPM's native build writes lowercase `.lproj` names.
    let root = try makeBundle(localizations: ["en-us", "pl-pl"])
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("\"shared\" = \"English source\";\n".utf8).write(
      to: root.appendingPathComponent("Contents/Resources/en-us.lproj/Localizable.strings")
    )
    let bundle = try #require(Bundle(path: root.path))

    // Act
    let resolver = Localization(bundle: bundle, preferredLanguages: ["pl-PL"])

    // Assert
    #expect(resolver.resolvedLanguage == "pl-pl")
    #expect(resolver.string("shared") == "English source")
  }

  @Test
  func resolverCachesLocaleDiscoveryAtInitialization() throws {
    // Arrange
    let root = try makeBundle(localizations: ["en-US", "fr-FR"])
    defer { try? FileManager.default.removeItem(at: root) }
    let bundle = try #require(Bundle(path: root.path))
    let resolver = Localization(bundle: bundle, preferredLanguages: ["fr-FR"])

    // Act
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Contents/Resources/de-DE.lproj"),
      withIntermediateDirectories: true
    )

    // Assert
    #expect(resolver.availableLocalizations == ["en-US", "fr-FR"])
    #expect(resolver.resolvedLanguage == "fr-FR")
    #expect(Localization.availableLocalizations(in: bundle) == ["de-DE", "en-US", "fr-FR"])
  }

  private func makeBundle(localizations: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSLocalization-\(UUID().uuidString).bundle"
    )
    let resources = root.appendingPathComponent("Contents/Resources")
    for localization in localizations {
      try FileManager.default.createDirectory(
        at: resources.appendingPathComponent("\(localization).lproj"),
        withIntermediateDirectories: true
      )
    }
    let info = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0"><dict><key>CFBundleIdentifier</key>
      <string>test.localization.\(UUID().uuidString)</string></dict></plist>
      """
    try Data(info.utf8).write(to: root.appendingPathComponent("Contents/Info.plist"))
    return root
  }
}
