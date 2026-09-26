import Foundation
import Testing
@testable import NPSBrowserApp

func waitForDownloadLoadCount(
  _ expectedCount: Int,
  fixture: WorkspaceVolumeSnapshotFixture
) async throws {
  for _ in 0..<200 {
    if await fixture.loadCount() >= expectedCount { return }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  Issue.record("Timed out waiting for \(expectedCount) download snapshot loads")
}

func waitForStreamObserverCount(
  _ expectedCount: Int,
  fixture: WorkspaceVolumeSnapshotFixture
) async throws {
  for _ in 0..<200 {
    if await fixture.streamObserverCount() >= expectedCount { return }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  Issue.record("Timed out waiting for \(expectedCount) download stream observers")
}

@MainActor
func waitForDownloadDetail(
  _ expectedDetail: String,
  in controller: DownloadActivityViewController
) async throws {
  for _ in 0..<200 {
    if controller.displayedEntries.first(where: { $0.id == "completed-volume-job" })?.detail
      == expectedDetail
    {
      return
    }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  Issue.record("Timed out waiting for download detail \(expectedDetail)")
}

func waitForCompletedDownloadLoadCount(
  _ expectedCount: Int,
  fixture: WorkspaceVolumeSnapshotFixture
) async throws {
  for _ in 0..<200 {
    if await fixture.completedLoadCount() >= expectedCount { return }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  Issue.record("Timed out waiting for \(expectedCount) completed download snapshot loads")
}

@MainActor
func waitForDisplayedIDs(
  _ expectedIDs: Set<String>,
  in controller: DownloadActivityViewController
) async throws {
  for _ in 0..<200 {
    if Set(controller.displayedEntries.map(\.id)) == expectedIDs { return }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  Issue.record("Timed out waiting for download rows \(expectedIDs)")
}

@MainActor
func waitForRevealAvailability(
  _ expectedAvailability: Bool,
  in controller: DownloadActivityViewController
) async throws {
  for _ in 0..<200 {
    if let completed = controller.displayedEntries.first(where: { $0.id == "completed-volume-job" }
    ), completed.canPerform(.reveal) == expectedAvailability {
      return
    }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  Issue.record("Timed out waiting for Reveal availability to become \(expectedAvailability)")
}
