import Foundation
import Testing
@testable import NPSCore

@Suite(.sourceEnglish)
struct SettingsErrorTests {
  @Test
  func invalidCatalogueURLNamesTheLocalizedSourceNotItsKey() {
    // Arrange
    let error = SettingsError.invalidCatalogueURL(.psvGames, "ftp://example.test/a.tsv")

    // Act
    let description = error.localizedDescription

    // Assert
    #expect(
      description
        == "The PS Vita Games catalog URL must be an absolute HTTP, HTTPS, or file URL: ftp://example.test/a.tsv"
    )
    #expect(!description.contains("src_"))
  }
}
