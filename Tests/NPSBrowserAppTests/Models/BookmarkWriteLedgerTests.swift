import Testing
@testable import NPSBrowserApp

@Suite(.sourceEnglish)
struct BookmarkWriteLedgerTests {
  @Test
  func beginWriteShowsTheNewStateAndNumbersWritesPerItem() {
    // Arrange
    var ledger = BookmarkWriteLedger()
    ledger.reset(to: ["A"])

    // Act
    let first = ledger.beginWrite("B", isBookmarked: true)
    let second = ledger.beginWrite("B", isBookmarked: false)
    let other = ledger.beginWrite("A", isBookmarked: false)

    // Assert
    #expect(first.generation == 1)
    #expect(second.generation == 2)
    #expect(other.generation == 1)
    #expect(!ledger.isCurrent(first.generation, for: "B"))
    #expect(ledger.isCurrent(second.generation, for: "B"))
    #expect(ledger.bookmarkedIDs.isEmpty)
    #expect(ledger.confirmedBookmarkedIDs == ["A"])
  }

  @Test
  func confirmedWriteUpdatesConfirmedStateEvenWhenSuperseded() {
    // Arrange
    var ledger = BookmarkWriteLedger()
    let first = ledger.beginWrite("A", isBookmarked: true)
    _ = ledger.beginWrite("A", isBookmarked: false)

    // Act
    ledger.confirmWrite("A", isBookmarked: true, generation: first.generation)

    // Assert
    #expect(ledger.confirmedBookmarkedIDs == ["A"])
    #expect(ledger.bookmarkedIDs.isEmpty)
  }

  @Test
  func rollBackPrefersPersistedStateOverConfirmedState() {
    // Arrange
    var ledger = BookmarkWriteLedger()
    ledger.reset(to: ["A"])
    let write = ledger.beginWrite("A", isBookmarked: false)

    // Act
    ledger.rollBack("A", persistedIDs: [], generation: write.generation)

    // Assert
    #expect(ledger.bookmarkedIDs.isEmpty)
    #expect(ledger.confirmedBookmarkedIDs.isEmpty)
  }

  @Test
  func rollBackFallsBackToConfirmedStateWhenPersistedStateIsUnknown() {
    // Arrange
    var ledger = BookmarkWriteLedger()
    ledger.reset(to: ["A"])
    let write = ledger.beginWrite("A", isBookmarked: false)

    // Act
    ledger.rollBack("A", persistedIDs: nil, generation: write.generation)

    // Assert
    #expect(ledger.bookmarkedIDs == ["A"])
    #expect(ledger.confirmedBookmarkedIDs == ["A"])
  }

  @Test
  func finishedWriteIsNotHandedToTheNextWriteAsPreceding() {
    // Arrange
    var ledger = BookmarkWriteLedger()
    let first = ledger.beginWrite("A", isBookmarked: true)
    ledger.track(Task {}, for: "A")

    // Act
    let whilePending = ledger.beginWrite("A", isBookmarked: false)
    ledger.track(Task {}, for: "A")
    ledger.confirmWrite("A", isBookmarked: true, generation: first.generation)
    let afterStaleConfirm = ledger.beginWrite("A", isBookmarked: true)
    ledger.track(Task {}, for: "A")
    ledger.confirmWrite("A", isBookmarked: true, generation: afterStaleConfirm.generation)
    let afterCurrentConfirm = ledger.beginWrite("A", isBookmarked: false)

    // Assert
    #expect(whilePending.precedingWrite != nil)
    #expect(afterStaleConfirm.precedingWrite != nil)
    #expect(afterCurrentConfirm.precedingWrite == nil)
  }
}
