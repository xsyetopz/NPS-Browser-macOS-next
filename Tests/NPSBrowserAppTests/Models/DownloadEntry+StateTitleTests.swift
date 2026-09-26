import NPSBrowserAppResources
import Testing
@testable import NPSBrowserApp

@Suite(.sourceEnglish)
struct DownloadEntryStateTitleTests {
  @Test
  func statusTextOverridesTheLocalizedStateName() {
    // Arrange
    var entry = DownloadEntry(
      id: "job",
      title: "Example",
      detail: "",
      state: .queued,
      progress: nil,
      completedFile: nil
    )

    // Act
    let stateTitle = entry.stateTitle
    entry.statusText = "Checking for update"

    // Assert
    #expect(entry.stateTitleKey == "downloads.state.queued")
    #expect(stateTitle == AppResources.localized("downloads.state.queued"))
    #expect(entry.stateTitle == "Checking for update")
  }
}
