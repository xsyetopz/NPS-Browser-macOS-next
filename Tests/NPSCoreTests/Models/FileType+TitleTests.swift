import Foundation
import Testing
@testable import NPSCore

@Suite(.sourceEnglish)
struct FileTypeTitleTests {
  @Test
  func everyFileTypeNamesADistinctCatalogTitle() {
    // Act
    let titles = FileType.allCases.map { $0.localizedTitleMessage.resolved() }

    // Assert
    #expect(FileType.Game.localizedTitleMessage.resolved() == "Games")
    #expect(FileType.RAP.localizedTitleMessage.resolved() == "RAP Licenses")
    #expect(Set(titles).count == FileType.allCases.count)
    #expect(titles.allSatisfy { !$0.contains(".") })
  }
}
