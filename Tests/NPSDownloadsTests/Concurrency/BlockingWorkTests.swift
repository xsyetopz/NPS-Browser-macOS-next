import Foundation
import Testing
@testable import NPSDownloads

@Suite(.sourceEnglish)
struct BlockingWorkTests {
  private struct Failure: Error, Equatable {}

  @Test
  func returnsTheValueProducedOffTheCooperativePool() async throws {
    // Act
    let isMainThread = try await BlockingWork.run { Thread.isMainThread }
    let value = try await BlockingWork.run { 21 * 2 }

    // Assert
    #expect(!isMainThread)
    #expect(value == 42)
  }

  @Test
  func propagatesThrownErrors() async {
    // Act / Assert
    await #expect(throws: Failure.self) { try await BlockingWork.run { throw Failure() } }
  }
}
