import Foundation
import Testing
@testable import NPSCore

@Suite(.sourceEnglish)
struct ConsoleTypeTitleTests {
  @Test
  func everyConsoleNamesADistinctCatalogTitle() {
    // Act
    let titles = ConsoleType.allCases.map { $0.localizedTitleMessage.resolved() }

    // Assert
    #expect(ConsoleType.PSV.localizedTitleMessage.resolved() == "PlayStation Vita")
    #expect(Set(titles).count == ConsoleType.allCases.count)
    #expect(titles.allSatisfy { !$0.hasPrefix("section.") })
  }
}
