import Foundation
import NPSCore
import Testing
@testable import NPSDownloads

@Suite(.sourceEnglish)
struct TransferFailureTests {
  @Test
  func describesItselfWithItsLocalizedMessage() {
    // Arrange
    let failure = TransferFailure(
      message: LocalizedMessage("error.download.transferEndedWithoutFile"),
      resumeData: nil
    )

    // Act
    let message = LocalizedMessage(failure)

    // Assert
    #expect(message == LocalizedMessage("error.download.transferEndedWithoutFile"))
    #expect(failure.localizedDescription == "The transfer ended without a downloaded file.")
  }
}
