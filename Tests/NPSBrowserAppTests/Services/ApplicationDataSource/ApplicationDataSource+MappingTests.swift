import Foundation
import NPSCore
import Testing
@testable import NPSDownloads
@testable import NPSBrowserApp

@Suite(.serialized, .sourceEnglish)
@MainActor
struct ApplicationDataSourceMappingTests {
  @Test
  func activeSnapshotWithoutProgressRatioMapsToUnknownLength() {
    func makeSnapshot(expectedByteCount: Int64?, errorMessage: String? = nil) -> DownloadSnapshot {
      DownloadSnapshot(
        id: UUID(),
        request: DownloadJobRequest(
          sourceURL: URL(string: "https://downloads.example/game.pkg")!,
          title: "Unknown Length Game",
          consoleType: "PSV",
          titleID: "PCSA00006",
          expectedByteCount: expectedByteCount
        ),
        state: .downloading,
        progress: 0,
        bytesReceived: 48 * 1024 * 1024,
        destinationDirectory: URL(fileURLWithPath: "/tmp/downloads", isDirectory: true),
        destinationURL: nil,
        packageVerified: false,
        compatibilityPatchDestinationURL: nil,
        compatibilityPatchVerified: false,
        extractedDirectoryURL: nil,
        legacyOutputLocationUnknown: nil,
        errorMessage: errorMessage,
        canResume: false,
        createdAt: Date(),
        updatedAt: Date()
      )
    }

    let unknownLength = ApplicationDataSource.downloadEntry(makeSnapshot(expectedByteCount: nil))
    #expect(unknownLength.state == .downloading)
    #expect(unknownLength.progress == nil)
    #expect(unknownLength.detail.hasPrefix("PCSA00006 ·"))

    let knownCatalogueSize = ApplicationDataSource.downloadEntry(
      makeSnapshot(expectedByteCount: 96 * 1024 * 1024)
    )
    #expect(knownCatalogueSize.progress == 0.5)

    let failed = ApplicationDataSource.downloadEntry(
      makeSnapshot(expectedByteCount: nil, errorMessage: "HTTP 503: server unavailable")
    )
    #expect(failed.detail == "HTTP 503: server unavailable")
  }

  @Test
  func downloadActivityInterfaceStringsHaveChineseTranslations() throws {
    // The native SwiftPM build system may lowercase `zh-CN.lproj`; resolve it
    // the way Foundation matches localizations.
    let stringsPath = try #require(
      Localization.moduleBundle.path(
        forResource: "Localizable",
        ofType: "strings",
        inDirectory: nil,
        forLocalization: "zh-CN"
      )
    )
    let localizationURL = URL(fileURLWithPath: stringsPath).deletingLastPathComponent()
    let chineseBundle = try #require(Bundle(url: localizationURL))
    let keys = [
      "downloads.count", "downloads.accessibility.label", "downloads.column.download",
      "downloads.column.status", "downloads.column.progress", "downloads.column.actions",
      "downloads.state.queued", "downloads.state.downloading", "downloads.state.paused",
      "downloads.state.failed", "downloads.state.verifying", "downloads.state.extracting",
      "downloads.state.complete", "downloads.progress.label",
      "downloads.progress.indeterminate.label", "downloads.progress.indeterminate.help",
      "downloads.progress.unavailable", "downloads.remove.confirm.title",
      "error.download.invalidResumeData", "error.download.interruptedWithResume",
      "error.download.closedWhileVerifying", "error.download.closedDuringExtraction",
      "error.download.transferEndedWithoutFile", "error.migration.legacyResumePreserved",
      "error.migration.legacyInterruptedWithoutResume", "downloads.remove.confirm.message",
      "downloads.remove.confirm.cancel", "downloads.remove.confirm.action",
    ]

    for key in keys {
      #expect(chineseBundle.localizedString(forKey: key, value: key, table: nil) != key)
    }

    // Download errors are localized where they are raised, not re-mapped by the app.
    #expect(
      DownloadCoordinatorError.invalidResumeData.localizedDescription
        == Localization.current.string("error.download.invalidResumeData")
    )
  }
}
