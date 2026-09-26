import Foundation
import NPSBrowserAppResources
import NPSCore
import Testing
@testable import NPSBrowserApp

@Suite(.serialized, .sourceEnglish)
@MainActor
struct CountTextTests {
  @Test
  func countsUseGroupingSeparatorsAndSingularForms() {
    // Arrange
    let resolver = Localization.current

    // Act
    let many = CountText.string(36_432, key: "status.items")
    let one = CountText.string(1, key: "status.items")

    // Assert
    #expect(many == resolver.plural("status.items", count: 36_432))
    #expect(one == resolver.plural("status.items", count: 1))
    #expect(!many.contains("36432"))
    #expect(!many.contains("status.items"))
  }
}
