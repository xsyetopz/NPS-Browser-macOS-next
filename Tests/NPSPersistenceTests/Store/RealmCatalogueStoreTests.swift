import Foundation
import NPSCore
import RealmSwift
import Testing
@testable import NPSPersistence

@Suite(.sourceEnglish)
struct RealmCatalogueStoreTests {
  @Test
  func catalogueAndBookmarkWritesAreImmediatelyObservable() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSPersistenceTests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let realmURL = directory.appendingPathComponent("catalogue.realm")
    let item = sampleItem(id: "PCSA00001", name: "Example Game")
    let store = try RealmCatalogueStore(fileURL: realmURL)

    try await store.replaceItems([item])
    #expect(try await store.allItems() == [item])
    #expect(try await store.isBookmarked(item.id) == false)

    try await store.setBookmarked(item, isBookmarked: true)
    #expect(try await store.isBookmarked(item.id))
    #expect(try await store.bookmarks() == [Bookmark(item: item)])

    try await store.setBookmarked(item, isBookmarked: false)
    #expect(try await store.isBookmarked(item.id) == false)
    #expect(try await store.bookmarks().isEmpty)
  }

  @Test
  func failedOpenLeavesTheOriginalRealmFileUntouched() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSPersistenceFailure-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let realmURL = directory.appendingPathComponent("corrupt.realm")
    let original = Data("not a realm database".utf8)
    try original.write(to: realmURL)
    let store = try RealmCatalogueStore(fileURL: realmURL)

    do {
      _ = try await store.allItems()
      Issue.record("Expected the corrupted Realm file to fail to open.")
    } catch { #expect(try Data(contentsOf: realmURL) == original) }
  }

  @Test
  func upgradesSchemaZeroAndBacksUpBeforeMigration() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSLegacyZero-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let realmURL = directory.appendingPathComponent("default.realm")
    let fixture = try copyFixture(named: "LegacySchema0", to: realmURL)
    #expect(try schemaVersionAtURL(realmURL) == 0)

    let backupsDirectory = directory.appendingPathComponent("Backups", isDirectory: true)
    let store = try RealmCatalogueStore(fileURL: realmURL, backupDirectory: backupsDirectory)
    let items = try await store.allItems()
    let bookmarks = try await store.bookmarks()
    let compatPacks = try await store.compatibilityPacks(kind: .pack)

    #expect(items.count == 1)
    #expect(items.first?.titleID == "PCSA00001")
    #expect(items.first?.name == "Legacy Game")
    #expect(items.first?.legacyPrimaryKey == "USGamePCSA00001CONTENT-PCSA00001")
    #expect(items.first?.originalName == nil)
    #expect(bookmarks.count == 1)
    #expect(bookmarks.first?.id == items.first?.id)
    #expect(compatPacks.count == 1)
    #expect(compatPacks.first?.titleID == "PCSA00001")
    #expect(compatPacks.first?.kind == .pack)
    #expect(compatPacks.first?.downloadURL.path.hasSuffix(".ppk") == true)
    #expect(compatPacks.first?.displayName == nil)
    #expect(try schemaVersionAtURL(realmURL) == RealmCatalogueStore.currentSchemaVersion)

    let backup = try #require(
      try FileManager.default.contentsOfDirectory(
        at: backupsDirectory,
        includingPropertiesForKeys: nil
      ).first
    )
    #expect(try schemaVersionAtURL(backup) == 0)
    #expect(try Data(contentsOf: backup) == Data(contentsOf: fixture))
  }

  @Test
  func upgradesSchemaOneWithoutChangingBookmarkOrItemFields() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSLegacyOne-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let realmURL = directory.appendingPathComponent("default.realm")
    let fixture = try copyFixture(named: "LegacySchema1", to: realmURL)
    #expect(try schemaVersionAtURL(realmURL) == 1)

    let backupsDirectory = directory.appendingPathComponent("Backups", isDirectory: true)
    let store = try RealmCatalogueStore(fileURL: realmURL, backupDirectory: backupsDirectory)
    let items = try await store.allItems()
    let bookmarks = try await store.bookmarks()
    let compatPacks = try await store.compatibilityPacks(kind: .pack)

    #expect(items.count == 1)
    #expect(items.first?.titleID == "PCSA00001")
    #expect(items.first?.name == "Legacy Game")
    #expect(items.first?.fileSize == 4096)
    #expect(bookmarks.count == 1)
    #expect(compatPacks.count == 1)
    #expect(compatPacks.first?.titleID == "PCSA00001")
    #expect(compatPacks.first?.displayName == nil)
    #expect(try schemaVersionAtURL(realmURL) == RealmCatalogueStore.currentSchemaVersion)

    let backups = try FileManager.default.contentsOfDirectory(
      at: backupsDirectory,
      includingPropertiesForKeys: nil
    )
    #expect(backups.count == 1)
    #expect(try schemaVersionAtURL(backups[0]) == 1)
    #expect(try Data(contentsOf: backups[0]) == Data(contentsOf: fixture))
  }

  @Test
  func compatibilityFeedUpdatesReplaceOnlyTheSelectedKind() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSCompatibilityStore-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try RealmCatalogueStore(
      fileURL: directory.appendingPathComponent("catalogue.realm")
    )
    let pack = try #require(
      CatalogParser.parseCompatibilityPacks(
        "PCSB01101/PCSB01101-03_650-01_00-01_00.ppk=Pack name",
        kind: .pack
      ).first
    )
    let patch = try #require(
      CatalogParser.parseCompatibilityPacks(
        "patch/PCSB01101/PCSB01101-03_650-02_03-01_00.ppk=Patch name",
        kind: .patch
      ).first
    )
    let replacement = try #require(
      CatalogParser.parseCompatibilityPacks(
        "PCSA00001/PCSA00001-03_650-01_00-01_00.ppk=Replacement pack",
        kind: .pack
      ).first
    )

    try await store.replaceCompatibilityPacks([pack], kind: .pack)
    try await store.replaceCompatibilityPacks([patch], kind: .patch)
    #expect(try await store.compatibilityPacks(kind: .pack) == [pack])
    #expect(try await store.compatibilityPacks(kind: .patch) == [patch])

    try await store.replaceCompatibilityPacks([replacement], kind: .pack)

    #expect(try await store.compatibilityPacks(kind: .pack) == [replacement])
    #expect(try await store.compatibilityPacks(kind: .patch) == [patch])
    #expect(try await store.compatibilityPacks().count == 2)
    await #expect(throws: CatalogueStoreError.mismatchedCompatibilityPackKind(expected: .pack)) {
      try await store.replaceCompatibilityPacks([patch], kind: .pack)
    }
    #expect(try await store.compatibilityPacks(kind: .pack) == [replacement])
  }

  private func copyFixture(named name: String, to destination: URL) throws -> URL {
    let fixture = try #require(Bundle.module.url(forResource: name, withExtension: "realm"))
    try FileManager.default.copyItem(at: fixture, to: destination)
    return fixture
  }

  private func sampleItem(id: String, name: String) -> CatalogItem {
    CatalogItem(
      titleID: id,
      region: "US",
      contentID: "CONTENT-\(id)",
      name: name,
      packageURL: URL(string: "https://cdn.example/\(id).pkg"),
      fileSize: 4_096,
      sha256: String(repeating: "a", count: 64),
      zrif: "license",
      consoleType: .PSV,
      fileType: .Game
    )
  }
}
