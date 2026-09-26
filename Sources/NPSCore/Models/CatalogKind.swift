import Foundation

public struct CatalogKind: Hashable, Sendable {
  public let console: ConsoleType
  public let fileType: FileType

  public init(console: ConsoleType, fileType: FileType) {
    self.console = console
    self.fileType = fileType
  }
}
