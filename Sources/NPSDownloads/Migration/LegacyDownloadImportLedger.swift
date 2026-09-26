import Foundation
import NPSCore

enum LegacyDownloadImportLedger {
  static func url(nextTo persistenceURL: URL) -> URL {
    URL(fileURLWithPath: persistenceURL.path + ".legacy-import", isDirectory: false)
  }

  static func read(at url: URL) throws -> String? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
      let data = try Data(contentsOf: url)
      guard let digest = String(data: data, encoding: .utf8),
        digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
      else {
        throw LegacyDownloadMigrationError.invalidImportLedger(
          LocalizedMessage("error.migration.ledgerNotDigest")
        )
      }
      return digest
    } catch let error as LegacyDownloadMigrationError { throw error } catch {
      throw LegacyDownloadMigrationError.invalidImportLedger(LocalizedMessage(error))
    }
  }

  static func write(_ digest: String, to url: URL) throws {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data(digest.utf8).write(to: url, options: .atomic)
    } catch {
      throw LegacyDownloadMigrationError.importLedgerWriteFailed(error.localizedDescription)
    }
  }
}
