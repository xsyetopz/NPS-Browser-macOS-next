import Foundation
import NPSCore
import Testing
@testable import NPSDownloads

@Suite(.sourceEnglish)
struct DownloadCoordinatorErrorTests {
  @Test
  func invalidTransitionNamesLocalizedStatesNotRawValues() {
    // Arrange
    let error = DownloadCoordinatorError.invalidTransition(from: .complete, to: .paused)
    let chinese = Localization(preferredLanguages: ["zh-CN"])

    // Act
    let english = error.localizedDescription
    let translated = Localization.$override.withValue(chinese) { error.localizedDescription }

    // Assert
    #expect(english == "Cannot change a download from Complete to Paused.")
    #expect(translated.contains("已暂停"))
    #expect(!translated.contains("paused"))
  }

  @Test
  func chineseInvalidTransitionInsertsNoSpacesAroundStateNames() {
    // Arrange
    let error = DownloadCoordinatorError.invalidTransition(from: .paused, to: .extracting)
    let chinese = Localization(preferredLanguages: ["zh-CN"])

    // Act
    let translated = Localization.$override.withValue(chinese) { error.localizedDescription }

    // Assert
    #expect(translated == "无法将下载从“已暂停”更改为“正在解包”。")
    #expect(!translated.contains(" "))
  }
}
