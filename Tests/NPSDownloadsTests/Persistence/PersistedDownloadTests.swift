import Foundation
import NPSCore
import Testing
@testable import NPSDownloads

@Suite(.sourceEnglish)
struct PersistedDownloadTests {
  private static func job(errorMessage: String? = nil) throws -> PersistedDownload {
    let url = try #require(URL(string: "https://example.test/game.pkg"))
    return PersistedDownload(
      id: UUID(),
      request: DownloadJobRequest(sourceURL: url, title: "Game", consoleType: "PSV"),
      state: .failed,
      progress: 0,
      bytesReceived: 0,
      destinationDirectory: FileManager.default.temporaryDirectory,
      errorMessage: errorMessage,
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 0)
    )
  }

  @Test
  func storedErrorsRenderInTheLanguageCurrentWhenDisplayed() throws {
    // Arrange
    let chinese = Localization(preferredLanguages: ["zh-CN"])
    var job = try Self.job()
    Localization.$override.withValue(chinese) {
      job.setError(DownloadCoordinatorError.invalidResumeData.localizedMessage)
    }
    let data = try PropertyListEncoder().encode([job])

    // Act
    let restored = try #require(
      try PropertyListDecoder().decode([PersistedDownload].self, from: data).first
    )
    let english = restored.snapshot.errorMessage
    let translated = Localization.$override.withValue(chinese) { restored.snapshot.errorMessage }

    // Assert
    #expect(restored.errorDetail == LocalizedMessage("error.download.invalidResumeData"))
    #expect(restored.errorMessage == chinese.string("error.download.invalidResumeData"))
    #expect(english == DownloadCoordinatorError.invalidResumeData.localizedDescription)
    #expect(english?.contains("resume data") == true)
    #expect(translated == chinese.string("error.download.invalidResumeData"))
  }

  @Test
  func recordsWithoutStructuredErrorsKeepTheirStoredText() throws {
    // Arrange
    let legacy = try Self.job(errorMessage: "Stored before structured errors")
    let data = try PropertyListEncoder().encode([legacy])
    let plist = try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]
    )

    // Act
    let restored = try #require(
      try PropertyListDecoder().decode([PersistedDownload].self, from: data).first
    )

    // Assert
    #expect(plist.first?["errorDetail"] == nil)
    #expect(restored.errorDetail == nil)
    #expect(restored.snapshot.errorMessage == "Stored before structured errors")
  }

  @Test
  func clearingTheErrorClearsBothForms() throws {
    // Arrange
    var job = try Self.job()
    job.setError(LocalizedMessage("error.download.restoredPaused"))

    // Act
    job.setError(nil)

    // Assert
    #expect(job.errorDetail == nil)
    #expect(job.errorMessage == nil)
    #expect(job.snapshot.errorMessage == nil)
  }
}
