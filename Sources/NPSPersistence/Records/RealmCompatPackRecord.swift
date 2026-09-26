import Foundation
import RealmSwift

// These Objective-C runtime names and persisted property names match the archived
// Realm schema. Do not rename them without a further migration.
@objc(CompatPack)
public final class RealmCompatPackRecord: Object {
  @Persisted(primaryKey: true)
  public var uuid: String = UUID().uuidString
  @Persisted
  public var titleId: String?
  @Persisted
  public var downloadUrl: String?
  @Persisted
  public var type: String?
  @Persisted
  public var name: String?
}
