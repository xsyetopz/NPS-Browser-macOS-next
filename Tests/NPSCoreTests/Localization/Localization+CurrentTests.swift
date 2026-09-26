import Foundation
import Testing
@testable import NPSCore

@Suite(.sourceEnglish)
struct LocalizationCurrentTests {
  @Test
  func overrideSelectsTheResolverForTheTaskAndItsChildren() async {
    // Arrange
    let chinese = Localization(preferredLanguages: ["zh-CN"])

    // Act
    let pinned = Localization.current.string("downloads.state.paused")
    let overridden = await Localization.$override.withValue(chinese) {
      await Task { Localization.current.string("downloads.state.paused") }.value
    }

    // Assert
    #expect(pinned == "Paused")
    #expect(overridden == "已暂停")
  }

  @Test
  func environmentLanguagesReplaceTheSystemOrder() {
    // Arrange
    let key = Localization.preferredLanguagesEnvironmentKey

    // Act
    let configured = Localization.ambientPreferredLanguages(
      environment: [key: "zh-CN, en-US"],
      system: ["fr-FR"]
    )
    let blank = Localization.ambientPreferredLanguages(environment: [key: " "], system: ["fr-FR"])
    let unset = Localization.ambientPreferredLanguages(environment: [:], system: ["fr-FR"])

    // Assert
    #expect(configured == ["zh-CN", "en-US"])
    #expect(blank == ["fr-FR"])
    #expect(unset == ["fr-FR"])
  }
}
