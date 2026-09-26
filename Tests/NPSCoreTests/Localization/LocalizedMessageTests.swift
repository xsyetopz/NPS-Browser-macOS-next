import Foundation
import Testing
@testable import NPSCore

@Suite(.sourceEnglish)
struct LocalizedMessageTests {
  @Test
  func rendersNestedMessagesAndPluralsInTheRequestedLanguage() {
    // Arrange
    let message = LocalizedMessage(
      "error.download.invalidTransition",
      .message(LocalizedMessage("downloads.state.paused")),
      .message(LocalizedMessage("downloads.state.queued"))
    )
    let chinese = Localization(preferredLanguages: ["zh-CN"])

    // Act
    let english = message.resolved()
    let translated = message.resolved(in: chinese)
    let plural = LocalizedMessage(
      "error.catalogue.wrongColumnCount",
      .integer(3),
      .plural("error.catalogue.columnCount", count: 1),
      .plural("error.catalogue.columnCount", count: 2)
    ).resolved()

    // Assert
    #expect(english == "Cannot change a download from Paused to Queued.")
    #expect(translated == "无法将下载从“已暂停”更改为“排队中”。")
    #expect(plural == "Catalog row 3 has 1 column; at least 2 columns are required.")
  }

  @Test
  func roundTripsThroughAPropertyList() throws {
    // Arrange
    let message = LocalizedMessage(
      "error.archive.unsafeEntry",
      .text("a/../b"),
      .message(LocalizedMessage("error.archive.reason.unsafePath")),
      .integer(7),
      .plural("status.items", count: 2)
    )

    // Act
    let data = try PropertyListEncoder().encode([message, .text("Stored")])
    let decoded = try PropertyListDecoder().decode([LocalizedMessage].self, from: data)

    // Assert
    #expect(decoded == [message, .text("Stored")])
    #expect(message.key == "error.archive.unsafeEntry")
    #expect(LocalizedMessage.text("Stored").key == nil)
  }

  @Test
  func wrapsStructuredErrorsAndKeepsOtherErrorDescriptions() {
    // Arrange
    let structured = CatalogParseError.missingUpdateURL
    let foreign = URLError(.timedOut)

    // Act
    let fromStructured = LocalizedMessage(structured)
    let fromForeign = LocalizedMessage(foreign)

    // Assert
    #expect(fromStructured == LocalizedMessage("error.catalogue.missingUpdateURL"))
    #expect(fromForeign == .text(foreign.localizedDescription))
  }
}
