import NPSBrowserAppResources
import Testing
@testable import NPSBrowserApp

@Suite(.sourceEnglish)
struct DownloadActionTitleTests {
  @Test
  func eachActionUsesItsLocalizedActionKey() {
    // Arrange
    let actions: [DownloadAction] = [.pause, .resume, .restart, .retryExtraction, .remove, .reveal]

    // Act
    let keys = actions.map(\.titleKey)

    // Assert
    #expect(
      keys == [
        "action.pause", "action.resume", "action.restart", "action.retryExtraction",
        "action.remove", "action.reveal",
      ]
    )
    #expect(DownloadAction.pause.title == AppResources.localized("action.pause"))
  }
}
