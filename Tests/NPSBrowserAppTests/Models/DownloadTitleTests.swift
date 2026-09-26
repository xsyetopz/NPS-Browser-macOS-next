import NPSCore
import Testing
@testable import NPSBrowserApp

@Suite(.sourceEnglish)
struct DownloadTitleTests {
  @Test
  func updateAndRAPTitlesNameTheEntry() {
    // Arrange
    let entry = browserEntry(id: "A", title: "Example")

    // Act
    let update = DownloadTitle.update(for: entry)
    let rap = DownloadTitle.rap(for: entry)

    // Assert
    #expect(update == "Example Update")
    #expect(rap == "Example RAP PCSA00007")
  }

  @Test
  func fileTitlesStayEnglishWhenDisplayTitlesAreLocalized() {
    // Arrange
    let entry = browserEntry(id: "A", title: "Example")
    let chinese = Localization(preferredLanguages: ["zh-CN"])

    // Act
    let (update, updateFile, rapFile) = Localization.$override.withValue(chinese) {
      (
        DownloadTitle.update(for: entry), DownloadTitle.updateFileTitle(for: entry),
        DownloadTitle.rapFileTitle(for: entry)
      )
    }

    // Assert
    #expect(update == "Example 更新")
    #expect(updateFile == "Example Update")
    #expect(rapFile == "Example RAP PCSA00007")
  }
}
