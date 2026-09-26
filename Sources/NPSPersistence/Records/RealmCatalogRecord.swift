import Foundation
import NPSCore
import RealmSwift

// These Objective-C runtime names and persisted property names match the archived
// Realm schema. Do not rename them without a further migration.
@objc(Item)
public final class RealmCatalogRecord: Object {
  @Persisted(primaryKey: true)
  public var uuid: String = UUID().uuidString
  @Persisted
  public var titleId: String?
  @Persisted
  public var region: String?
  @Persisted
  public var contentId: String?
  @Persisted
  public var consoleType: String?
  @Persisted
  public var fileType: String?
  @Persisted
  public var name: String?
  @Persisted
  public var pkgDirectLink: String?
  @Persisted
  public var rap: String?
  @Persisted
  public var downloadRapFile: String?
  @Persisted
  public var zrif: String?
  @Persisted
  public var requiredFw: Float?
  @Persisted
  public var lastModificationDate: Date?
  @Persisted
  public var fileSize: Int64?
  @Persisted
  public var sha256: String?
  @Persisted
  public var originalName: String?
  @Persisted
  public var pk: String = ""

  convenience init(item: CatalogItem) {
    self.init()
    titleId = item.titleID
    region = item.region
    contentId = item.contentID
    consoleType = item.consoleType.rawValue
    fileType = item.fileType.rawValue
    name = item.name
    pkgDirectLink = item.packageURL?.absoluteString
    rap = item.rap
    downloadRapFile = item.rapDownloadURL?.absoluteString
    zrif = item.zrif
    requiredFw = item.requiredFirmware
    lastModificationDate = item.lastModified
    fileSize = item.fileSize
    sha256 = item.sha256
    originalName = item.originalName
    pk = item.legacyPrimaryKey
  }
}
