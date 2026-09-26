import Foundation
import NPSCore
import Testing
@testable import NPSDownloads

@Suite(.sourceEnglish)
struct PackageExtractionErrorTests {
  @Test
  func launchFailureDoesNotWrapAnExtractionErrorTwice() {
    // Arrange
    let logFailure = PackageExtractionError.launchFailed(
      LocalizedMessage("error.extraction.logCreationFailed")
    )

    // Act
    let wrapped = PackageExtractionError.launchFailure(wrapping: logFailure)
    let text = wrapped.localizedDescription

    // Assert
    #expect(LocalizedMessage(wrapped) == LocalizedMessage(logFailure))
    #expect(text.hasPrefix("pkg2zip could not start. Cannot create a temporary log file. The"))
    #expect(text.components(separatedBy: "could not start").count == 2)
    #expect(!text.contains(".."))
  }

  @Test
  func launchFailureWrapsOtherErrorsOnce() {
    // Arrange
    let posixError = POSIXError(.ENOENT)

    // Act
    let wrapped = PackageExtractionError.launchFailure(wrapping: posixError)

    // Assert
    #expect(
      LocalizedMessage(wrapped)
        == LocalizedMessage(
          "error.extraction.launchFailed",
          .message(.text(posixError.localizedDescription))
        )
    )
  }
}
