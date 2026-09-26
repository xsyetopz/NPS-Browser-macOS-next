import AppKit
import Foundation
import Testing
@testable import NPSBrowserApp

@Suite(.serialized, .sourceEnglish)
@MainActor
struct DownloadActivityViewControllerTests {
  @Test
  func downloadRowsExposeOnlyStateValidActions() throws {
    let controller = DownloadActivityViewController()
    _ = controller.view
    let entries = activityFixtures()
    controller.setEntries(entries)
    let actionColumn = try #require(
      controller.tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("actions"))
    )
    let expectedActions: [[DownloadAction]] = [
      [.pause, .remove], [.pause, .remove], [.resume, .remove], [.restart, .remove],
      [.retryExtraction, .restart, .reveal, .remove], [.pause, .remove], [.reveal, .remove],
    ]
    let statusColumn = try #require(
      controller.tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("state"))
    )

    for row in entries.indices {
      let cell = try #require(
        controller.tableView(controller.tableView, viewFor: actionColumn, row: row)
      )
      let buttons = descendantViews(of: cell).compactMap { $0 as? NSButton }
      #expect(Set(buttons.map(\.tag)) == Set(expectedActions[row].map(\.rawValue)))
      #expect(
        buttons.allSatisfy { button in
          button.accessibilityLabel() == "\(button.title), \(entries[row].title)"
        }
      )
      let statusCell = try #require(
        controller.tableView(controller.tableView, viewFor: statusColumn, row: row)
      )
      #expect(
        descendantViews(of: statusCell).compactMap { $0 as? NSTextField }.contains {
          $0.stringValue == entries[row].stateTitle
        }
      )
    }
    #expect(entries[0].requiresRemovalConfirmation)
    #expect(entries[1].requiresRemovalConfirmation)
    #expect(entries[2].requiresRemovalConfirmation)
    #expect(!entries[3].requiresRemovalConfirmation)
    #expect(!entries[6].requiresRemovalConfirmation)
  }

  @Test
  func progressAndFailureDetailsHaveAccessibleNamesAndValues() throws {
    let controller = DownloadActivityViewController()
    _ = controller.view
    let entries = activityFixtures()
    controller.setEntries(entries)
    let progressColumn = try #require(
      controller.tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("progress"))
    )
    let downloadingRow = try #require(entries.firstIndex { $0.id == "downloading" })
    let progressCell = try #require(
      controller.tableView(controller.tableView, viewFor: progressColumn, row: downloadingRow)
    )
    let progress = try #require(
      descendantViews(of: progressCell).compactMap { $0 as? NSProgressIndicator }.first
    )
    #expect(progress.accessibilityLabel()?.contains("Example Downloading Game") == true)
    #expect(progress.minValue == 0)
    #expect(progress.maxValue == 1)
    #expect(progress.doubleValue == 0.42)
    #expect(progress.accessibilityValue()?.doubleValue == 0.42)

    let titleColumn = try #require(
      controller.tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("title"))
    )
    let failedRow = try #require(entries.firstIndex { $0.id == "failed" })
    let failedCell = try #require(
      controller.tableView(controller.tableView, viewFor: titleColumn, row: failedRow)
    )
    let rowLabel = try #require(failedCell.accessibilityLabel())
    #expect(rowLabel.contains("Example Failed Game"))
    #expect(rowLabel.contains("Failed"))
    #expect(rowLabel.contains("HTTP 503: server unavailable; retry the transfer"))
    let visibleError = try #require(
      descendantViews(of: failedCell).compactMap { $0 as? NSTextField }.first {
        $0.stringValue == "HTTP 503: server unavailable; retry the transfer"
      }
    )
    #expect(visibleError.maximumNumberOfLines == 0)
    #expect(visibleError.lineBreakMode == .byWordWrapping)
    #expect(visibleError.toolTip == visibleError.stringValue)
    let failedHeight = controller.tableView(controller.tableView, heightOfRow: failedRow)
    #expect(failedHeight > 54)
    #expect(visibleError.stringValue == entries[failedRow].detail)
    #expect(entries[failedRow].availableActions == [.restart, .remove])
  }

  @Test
  func onlyRealisticExtractionAndCompletedFixturesOfferReveal() throws {
    let entries = activityFixtures()
    let transferFailure = try #require(entries.first { $0.id == "failed" })
    let extractionFailure = try #require(entries.first { $0.id == "extract-failed" })
    let completed = try #require(entries.first { $0.id == "complete" })

    #expect(transferFailure.completedFile == nil)
    #expect(!transferFailure.canPerform(.reveal))
    #expect(
      extractionFailure.completedFile.map { FileManager.default.fileExists(atPath: $0.path) }
        == true
    )
    #expect(completed.completedFile.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    #expect(extractionFailure.canPerform(.retryExtraction))
  }

  @Test
  func unknownLengthActiveTransferUsesAccessibleIndeterminateProgress() throws {
    let controller = DownloadActivityViewController()
    _ = controller.view
    let unknownLength = DownloadEntry(
      id: "unknown-length",
      title: "Unknown Length Game",
      detail: "PCSA00006 · 48 MB received",
      state: .downloading,
      progress: nil,
      completedFile: nil,
      canPause: true
    )
    controller.setEntries([unknownLength])
    let progressColumn = try #require(
      controller.tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("progress"))
    )
    let progressCell = try #require(
      controller.tableView(controller.tableView, viewFor: progressColumn, row: 0)
    )
    let indicator = try #require(
      descendantViews(of: progressCell).compactMap { $0 as? NSProgressIndicator }.first
    )

    #expect(indicator.isIndeterminate)
    #expect(indicator.accessibilityLabel()?.contains(unknownLength.title) == true)
    #expect(indicator.accessibilityHelp()?.isEmpty == false)
  }

  @Test
  func keyboardSelectionRoutesTheVisibleRowActionToItsJob() throws {
    let controller = DownloadActivityViewController()
    _ = controller.view
    controller.setEntries(activityFixtures())
    controller.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

    let downArrow = try #require(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{f701}",
        charactersIgnoringModifiers: "\u{f701}",
        isARepeat: false,
        keyCode: 125
      )
    )
    controller.tableView.keyDown(with: downArrow)
    #expect(controller.tableView.selectedRow == 1)
    #expect(controller.selectedEntry?.id == "downloading")

    var routedAction: (String, DownloadAction)?
    controller.onAction = { entry, action in routedAction = (entry.id, action) }
    let actionColumn = try #require(
      controller.tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("actions"))
    )
    let cell = try #require(
      controller.tableView(
        controller.tableView,
        viewFor: actionColumn,
        row: controller.tableView.selectedRow
      )
    )
    let pauseButton = try #require(
      descendantViews(of: cell).compactMap { $0 as? NSButton }.first {
        $0.tag == DownloadAction.pause.rawValue
      }
    )
    pauseButton.performClick(nil)
    #expect(routedAction?.0 == "downloading")
    #expect(routedAction?.1 == .pause)
  }

  @Test
  func capturesDownloadActivityInLightAndDarkAppearance() throws {
    let lightURL = URL(fileURLWithPath: "/tmp/nps-download-activity-light.png")
    let darkURL = URL(fileURLWithPath: "/tmp/nps-download-activity-dark.png")
    let lightData = try renderActivityAppearance(.aqua, to: lightURL)
    let darkData = try renderActivityAppearance(.darkAqua, to: darkURL)

    #expect(lightData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    #expect(darkData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    #expect(lightData != darkData)
  }
}

@MainActor
@Test(.sourceEnglish)
func extractingDownloadDoesNotOfferRemovalAnywhere() {
  let extracting = DownloadEntry(
    id: "extracting",
    title: "Example",
    detail: "PCSA00007",
    state: .extracting,
    progress: nil,
    completedFile: nil,
    canRemove: false
  )

  #expect(!extracting.availableActions.contains(.remove))
  #expect(!extracting.canPerform(.remove))

  let failedExtraction = DownloadEntry(
    id: "failed-extraction",
    title: "Example",
    detail: "Extraction failed",
    state: .failed,
    progress: 1,
    completedFile: URL(fileURLWithPath: "/tmp/verified-example.pkg"),
    canRestart: true,
    canRetryExtraction: true
  )
  #expect(failedExtraction.canPerform(.restart))
  #expect(failedExtraction.canPerform(.retryExtraction))
}

@MainActor
private func renderActivityAppearance(
  _ appearanceName: NSAppearance.Name,
  to destination: URL
) throws -> Data {
  let controller = DownloadActivityViewController()
  let contentView = controller.view
  contentView.appearance = NSAppearance(named: appearanceName)
  contentView.frame = NSRect(x: 0, y: 0, width: 1000, height: 560)
  controller.setEntries(activityFixtures())
  contentView.layoutSubtreeIfNeeded()
  contentView.displayIfNeeded()
  let bitmap = try #require(contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds))
  contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
  let png = try #require(bitmap.representation(using: .png, properties: [:]))
  try png.write(to: destination, options: .atomic)
  return png
}

@MainActor
private func descendantViews(of view: NSView) -> [NSView] {
  [view] + view.subviews.flatMap(descendantViews)
}

private func activityFixtures() -> [DownloadEntry] {
  let extractionPackage = fixtureFile(named: "verified-extraction.pkg")
  let completedPackage = fixtureFile(named: "completed.pkg")
  return [
    DownloadEntry(
      id: "queued",
      title: "Example Queued Game",
      detail: "PCSA00001 · 0 bytes",
      state: .queued,
      progress: 0,
      completedFile: nil,
      canPause: true
    ),
    DownloadEntry(
      id: "downloading",
      title: "Example Downloading Game",
      detail: "PCSA00002 · 42 MB",
      state: .downloading,
      progress: 0.42,
      completedFile: nil,
      canPause: true
    ),
    DownloadEntry(
      id: "paused",
      title: "Example Paused Game",
      detail: "PCSA00003 · 12 MB",
      state: .paused,
      progress: 0.62,
      completedFile: nil,
      canResume: true
    ),
    DownloadEntry(
      id: "failed",
      title: "Example Failed Game",
      detail: "HTTP 503: server unavailable; retry the transfer",
      state: .failed,
      progress: 0.71,
      completedFile: nil,
      canRestart: true,
      canRetryExtraction: false
    ),
    DownloadEntry(
      id: "extract-failed",
      title: "Example Extraction Failure",
      detail: "pkg2zip failed with exit code 23: fixture output was not recognized.",
      state: .failed,
      progress: 1,
      completedFile: extractionPackage,
      canRestart: true,
      canRetryExtraction: true
    ),
    DownloadEntry(
      id: "unknown-length",
      title: "Example Unknown-Length Game",
      detail: "PCSA00006 · 48 MB received",
      state: .downloading,
      progress: nil,
      completedFile: nil,
      canPause: true
    ),
    DownloadEntry(
      id: "complete",
      title: "Example Complete Game",
      detail: "PCSA00005 · 54 MB",
      state: .complete,
      progress: 1,
      completedFile: completedPackage
    ),
  ]
}

private func fixtureFile(named name: String) -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "nps-download-activity-fixtures",
    isDirectory: true
  )
  try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let file = directory.appendingPathComponent(name)
  try? Data("download activity fixture".utf8).write(to: file, options: .atomic)
  return file
}
