import NPSCore
import Testing

/// Binds `Localization.override` to source English around each test, so text
/// assertions hold whatever language the Mac (or `NPS_PREFERRED_LANGUAGES`) prefers.
struct SourceEnglishTrait: TestTrait, SuiteTrait, TestScoping {
  static let localization = Localization(preferredLanguages: [Localization.sourceLocalization])

  var isRecursive: Bool { true }

  func provideScope(
    for test: Test,
    testCase: Test.Case?,
    performing function: @Sendable () async throws -> Void
  ) async throws {
    try await Localization.$override.withValue(Self.localization) { try await function() }
  }
}

extension Trait where Self == SourceEnglishTrait {
  /// Pins the UI language of a suite or test to source English (`en-US`).
  static var sourceEnglish: Self { Self() }
}
