import Foundation
import NPSCore
import RealmSwift

/// Owns all local Realm configuration and access. Each Realm instance is opened,
/// used, and released in one synchronous actor operation.
public actor RealmCatalogueStore {
  public static let currentSchemaVersion: UInt64 = 2

  private let configuration: Realm.Configuration
  private let backupDirectory: URL?

  public init(fileURL: URL? = nil, backupDirectory: URL? = nil) throws {
    var configuration = Realm.Configuration.defaultConfiguration
    if let fileURL {
      guard fileURL.isFileURL, fileURL.path.hasPrefix("/") else {
        throw CatalogueStoreError.invalidRealmURL(fileURL)
      }
      configuration.fileURL = fileURL.standardizedFileURL
    }
    configuration.schemaVersion = Self.currentSchemaVersion
    configuration.objectTypes = [
      RealmCatalogRecord.self, RealmSavedBookmark.self, RealmCompatPackRecord.self,
    ]
    configuration.migrationBlock = { migration, oldSchemaVersion in
      // Schema 0 acquired `pk` in the archived application. Keep all values,
      // repairing only that derived field while migrating to the maintained schema.
      guard oldSchemaVersion == 0 else { return }
      migration.enumerateObjects(ofType: "Item") { oldObject, newObject in
        guard let oldObject, let newObject else { return }
        let region = oldObject["region"] as? String
        let fileType = oldObject["fileType"] as? String
        let titleID = oldObject["titleId"] as? String
        let contentID = oldObject["contentId"] as? String
        if let region, let fileType, let titleID, let contentID {
          newObject["pk"] = "\(region)\(fileType)\(titleID)\(contentID)"
        } else {
          // Preserve malformed/incomplete legacy rows; do not discard the Realm.
          newObject["pk"] = ""
        }
      }
    }
    self.configuration = configuration
    self.backupDirectory = backupDirectory
  }

  public func allItems() throws -> [CatalogItem] {
    let realm = try openRealm()
    return realm.objects(RealmCatalogRecord.self).compactMap(Self.value(from:))
  }

  public func replaceItems(_ items: [CatalogItem]) throws {
    let realm = try openRealm()
    try realm.write {
      realm.delete(realm.objects(RealmCatalogRecord.self))
      for item in items {
        let record = RealmCatalogRecord(item: item)
        realm.add(record)
      }
    }
  }

  public func bookmarks() throws -> [Bookmark] {
    let realm = try openRealm()
    return realm.objects(RealmSavedBookmark.self).compactMap(Self.value(from:))
  }

  public func compatibilityPacks(kind: CompatibilityPackKind? = nil) throws -> [CompatibilityPack] {
    let realm = try openRealm()
    var records = realm.objects(RealmCompatPackRecord.self)
    if let kind { records = records.filter("type == %@", kind.rawValue) }
    return records.compactMap(Self.value(from:))
  }

  /// Replaces only the selected legacy compatibility-feed type.
  public func replaceCompatibilityPacks(
    _ packs: [CompatibilityPack],
    kind: CompatibilityPackKind
  ) throws {
    guard packs.allSatisfy({ $0.kind == kind }) else {
      throw CatalogueStoreError.mismatchedCompatibilityPackKind(expected: kind)
    }
    let realm = try openRealm()
    try realm.write {
      let existing = realm.objects(RealmCompatPackRecord.self).filter("type == %@", kind.rawValue)
      realm.delete(existing)
      for pack in packs {
        let record = RealmCompatPackRecord()
        record.uuid = pack.id
        record.titleId = pack.titleID
        record.downloadUrl = pack.downloadURL.absoluteString
        record.type = kind.rawValue
        record.name = pack.displayName
        realm.add(record)
      }
    }
  }

  /// Persists the bookmark change before returning to the caller.
  public func setBookmarked(_ item: CatalogItem, isBookmarked: Bool) throws {
    let realm = try openRealm()
    let id = item.id
    if let existing = realm.object(ofType: RealmSavedBookmark.self, forPrimaryKey: id) {
      guard !isBookmarked else { return }
      try realm.write { realm.delete(existing) }
      return
    }
    guard isBookmarked else { return }
    try realm.write {
      let record = RealmSavedBookmark(bookmark: Bookmark(item: item))
      realm.add(record, update: .modified)
    }
  }

  public func isBookmarked(_ id: String) throws -> Bool {
    let realm = try openRealm()
    return realm.object(ofType: RealmSavedBookmark.self, forPrimaryKey: id) != nil
  }

  public func isBookmarked(_ item: CatalogItem) throws -> Bool { try isBookmarked(item.id) }

  /// Exposes the backup path for diagnostics and migration tests. It never opens a Realm.
  public func backupURLForExistingFile() throws -> URL? {
    guard let fileURL = configuration.fileURL, FileManager.default.fileExists(atPath: fileURL.path)
    else { return nil }
    let version = try schemaVersionAtURL(fileURL)
    guard version < Self.currentSchemaVersion else { return nil }
    return try makeBackup(of: fileURL, schemaVersion: version)
  }

  private func openRealm() throws -> Realm {
    guard let fileURL = configuration.fileURL else {
      throw CatalogueStoreError.invalidRealmURL(URL(fileURLWithPath: ""))
    }
    let parent = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: fileURL.path) {
      let storedVersion = try schemaVersionAtURL(fileURL)
      if storedVersion < Self.currentSchemaVersion {
        _ = try makeBackup(of: fileURL, schemaVersion: storedVersion)
      }
    }
    return try Realm(configuration: configuration)
  }

  private func makeBackup(of fileURL: URL, schemaVersion: UInt64) throws -> URL {
    let directory =
      backupDirectory
      ?? fileURL.deletingLastPathComponent().appendingPathComponent(
        "RealmBackups",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(
      of: ":",
      with: "-"
    )
    let stem = fileURL.deletingPathExtension().lastPathComponent
    var destination = directory.appendingPathComponent(
      "\(stem)-schema-\(schemaVersion)-\(timestamp).realm"
    )
    if FileManager.default.fileExists(atPath: destination.path) {
      destination = directory.appendingPathComponent(
        "\(stem)-schema-\(schemaVersion)-\(UUID().uuidString).realm"
      )
    }
    try FileManager.default.copyItem(at: fileURL, to: destination)
    return destination
  }

  private static func value(from record: RealmCatalogRecord) -> CatalogItem? {
    guard let consoleType = record.consoleType.flatMap(ConsoleType.init(rawValue:)),
      let fileType = record.fileType.flatMap(FileType.init(rawValue:))
    else { return nil }
    return CatalogItem(
      titleID: record.titleId ?? "",
      region: record.region,
      contentID: record.contentId,
      name: record.name ?? "",
      packageURL: record.pkgDirectLink.flatMap(URL.init(string:)),
      lastModified: record.lastModificationDate,
      fileSize: record.fileSize,
      sha256: record.sha256,
      zrif: record.zrif,
      originalName: record.originalName,
      requiredFirmware: record.requiredFw,
      rap: record.rap,
      rapDownloadURL: record.downloadRapFile.flatMap(URL.init(string:)),
      consoleType: consoleType,
      fileType: fileType
    )
  }

  private static func value(from record: RealmSavedBookmark) -> Bookmark? {
    guard let id = record.uuid else { return nil }
    return Bookmark(
      id: id,
      titleID: record.titleId,
      downloadURL: record.downloadUrl.flatMap(URL.init(string:)),
      name: record.name,
      fileType: record.fileType,
      consoleType: record.consoleType,
      zrif: record.zrif
    )
  }

  private static func value(from record: RealmCompatPackRecord) -> CompatibilityPack? {
    guard let titleID = record.titleId, let rawURL = record.downloadUrl,
      let kindValue = record.type, let kind = CompatibilityPackKind(rawValue: kindValue),
      let url = URL(string: rawURL), url.scheme?.lowercased() == "https",
      url.host?.lowercased() == "gitlab.com",
      url.path.hasPrefix("/nopaystation_repos/nps_compati_packs/raw/master/")
    else { return nil }
    return CompatibilityPack(
      titleID: titleID,
      downloadURL: url,
      kind: kind,
      displayName: record.name
    )
  }
}
