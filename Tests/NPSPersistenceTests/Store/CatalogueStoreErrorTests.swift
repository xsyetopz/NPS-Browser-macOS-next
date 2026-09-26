import Foundation
import NPSCore
import Testing
@testable import NPSPersistence

@Suite(.sourceEnglish)
struct CatalogueStoreErrorTests {
  @Test
  func mismatchedKindNamesTheLocalizedCategoryNotTheRawValue() {
    // Arrange
    let error = CatalogueStoreError.mismatchedCompatibilityPackKind(expected: .patch)
    let chinese = Localization(preferredLanguages: ["zh-CN"])

    // Act
    let english = error.localizedDescription
    let translated = Localization.$override.withValue(chinese) { error.localizedDescription }

    // Assert
    #expect(english == "Every entry must belong to Compatibility Pack Patches.")
    #expect(translated == "每个条目都必须属于兼容包补丁。")
    #expect(!english.contains("CompatPatch"))
  }
}
