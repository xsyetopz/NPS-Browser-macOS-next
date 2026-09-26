import Foundation
import Testing
@testable import NPSBrowserApp

@Suite(.sourceEnglish)
struct DownloadEntryActionsTests {
  @Test
  func actionsFollowTheEntryFlagsInDisplayOrder() {
    // Arrange
    let entry = DownloadEntry(
      id: "job",
      title: "Example",
      detail: "",
      state: .failed,
      progress: 1,
      completedFile: URL(fileURLWithPath: "/tmp/example.pkg"),
      canPause: true,
      canResume: true,
      canRestart: true,
      canRetryExtraction: true
    )

    // Act
    let actions = entry.availableActions

    // Assert
    #expect(actions == [.pause, .resume, .retryExtraction, .restart, .reveal, .remove])
  }

  @Test
  func revealNeedsACompletedFileAndRemoveNeedsPermission() {
    // Arrange
    let entry = DownloadEntry(
      id: "job",
      title: "Example",
      detail: "",
      state: .extracting,
      progress: nil,
      completedFile: nil,
      canRemove: false
    )

    // Act
    let canReveal = entry.canPerform(.reveal)
    let canRemove = entry.canPerform(.remove)

    // Assert
    #expect(entry.availableActions.isEmpty)
    #expect(!canReveal)
    #expect(!canRemove)
  }
}
