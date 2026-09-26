import Foundation
import Testing
@testable import NPSBrowserApp

@Suite(.sourceEnglish)
struct PendingDownloadsTests {
  @Test
  func placeholdersUsePendingIDsAndSharedJobTitles() {
    // Arrange
    let entry = browserEntry(id: "A", title: "Example")

    // Act
    let package = PendingDownloads.packagePlaceholder(for: entry)
    let update = PendingDownloads.updatePlaceholder(for: entry)
    let rap = PendingDownloads.rapPlaceholder(for: entry)

    // Assert
    #expect(package.id == "pending-A")
    #expect(update.id == "pending-update-A")
    #expect(update.title == DownloadTitle.update(for: entry))
    #expect(rap.id == "pending-rap-A")
    #expect(rap.title == DownloadTitle.rap(for: entry))
    #expect([package, update, rap].allSatisfy { $0.state == .queued && !$0.canRemove })
  }

  @Test
  func aKeyHoldsOnePlaceholderAndOnlyItsJobCanRemoveIt() {
    // Arrange
    let placeholder = PendingDownloads.packagePlaceholder(for: browserEntry(id: "A", title: "A"))
    let firstJob = UUID()
    var pending = PendingDownloads()

    // Act
    let addedFirst = pending.add(key: "A", jobID: firstJob, placeholder: placeholder)
    let addedSecond = pending.add(key: "A", jobID: UUID(), placeholder: placeholder)
    let removedByOtherJob = pending.remove(key: "A", jobID: UUID())
    let rowsBeforeRemoval = pending.merged(with: [])
    let removedByOwnJob = pending.remove(key: "A", jobID: firstJob)

    // Assert
    #expect(addedFirst)
    #expect(!addedSecond)
    #expect(!removedByOtherJob)
    #expect(rowsBeforeRemoval.map(\.id) == ["pending-A"])
    #expect(removedByOwnJob)
    #expect(pending.merged(with: []).isEmpty)
  }

  @Test
  func snapshotContainingTheRequestedJobReplacesOnlyItsPlaceholder() {
    // Arrange
    let jobA = UUID()
    let jobB = UUID()
    var pending = PendingDownloads()
    pending.add(
      key: "A",
      jobID: jobA,
      placeholder: PendingDownloads.packagePlaceholder(for: browserEntry(id: "A", title: "A"))
    )
    pending.add(
      key: "B",
      jobID: jobB,
      placeholder: PendingDownloads.packagePlaceholder(for: browserEntry(id: "B", title: "B"))
    )
    let snapshot = [
      DownloadEntry(
        id: jobA.uuidString,
        title: "A",
        detail: "",
        state: .downloading,
        progress: 0.5,
        completedFile: nil
      )
    ]

    // Act
    pending.resolve(against: snapshot)
    let rows = pending.merged(with: snapshot)

    // Assert
    #expect(rows.map(\.id) == [jobA.uuidString, "pending-B"])
  }
}
