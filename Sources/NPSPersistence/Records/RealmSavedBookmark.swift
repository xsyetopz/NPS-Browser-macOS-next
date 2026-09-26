import Foundation
import NPSCore
import RealmSwift

// These Objective-C runtime names and persisted property names match the archived
// Realm schema. Do not rename them without a further migration.
@objc(Bookmark)
public final class RealmSavedBookmark: Object {
  @Persisted(primaryKey: true)
  public var uuid: String?
  @Persisted
  public var titleId: String?
  @Persisted
  public var downloadUrl: String?
  @Persisted
  public var name: String?
  @Persisted
  public var fileType: String?
  @Persisted
  public var consoleType: String?
  @Persisted
  public var zrif: String?

  convenience init(bookmark: Bookmark) {
    self.init()
    uuid = bookmark.id
    titleId = bookmark.titleID
    downloadUrl = bookmark.downloadURL?.absoluteString
    name = bookmark.name
    fileType = bookmark.fileType
    consoleType = bookmark.consoleType
    zrif = bookmark.zrif
  }
}
