import Foundation

extension Localization {
  /// Environment variable that replaces the system language order for `shared`,
  /// as a comma-separated list of tags such as `zh-CN,en-US`. It lets a test run
  /// or a debug launch simulate another UI language without `defaults write`.
  public static let preferredLanguagesEnvironmentKey = "NPS_PREFERRED_LANGUAGES"

  /// Resolver for the current task: `override` when set, otherwise `shared`.
  public static var current: Localization { override ?? shared }

  /// Task-scoped resolver. Tests bind it to pin one language regardless of
  /// the Mac's preferences; child tasks inherit it.
  @TaskLocal
  public static var override: Localization?

  static func ambientPreferredLanguages(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    system: [String] = Locale.preferredLanguages
  ) -> [String] {
    let configured = environment[preferredLanguagesEnvironmentKey]?.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespaces)
    }.filter { !$0.isEmpty }
    guard let configured, !configured.isEmpty else { return system }
    return configured
  }
}
