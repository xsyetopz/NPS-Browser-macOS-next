import CryptoKit
import Foundation
import NPSCore

enum LegacyDownloadMigration {
  static func merge(
    data: Data,
    destinationRoot: URL,
    existing: [PersistedDownload],
    now: Date = Date()
  ) throws -> [PersistedDownload] {
    let archive: LegacyDownloadList
    do { archive = try PropertyListDecoder().decode(LegacyDownloadList.self, from: data) } catch {
      throw LegacyDownloadMigrationError.malformedArchive(error.localizedDescription)
    }

    var jobs = existing
    var occupiedPaths = Set(
      existing.flatMap { job in
        [job.destinationURL?.path, job.compatibilityPatchDestinationURL?.path].compactMap { $0 }
      }
    )

    // Decode and validate the whole archive before returning any new jobs.
    let imported = try archive.items.enumerated().map { index, item in
      try migrate(
        item,
        index: index,
        destinationRoot: destinationRoot,
        occupiedPaths: &occupiedPaths,
        now: now
      )
    }
    for job in imported {
      if jobs.contains(where: { $0.id == job.id || sameLegacyDownload($0, job) }) { continue }
      jobs.append(job)
    }
    return jobs
  }

  private static func migrate(
    _ item: LegacyDownloadItem,
    index: Int,
    destinationRoot: URL,
    occupiedPaths: inout Set<String>,
    now: Date
  ) throws -> PersistedDownload {
    guard let sourceURL = item.downloadUrl, let scheme = sourceURL.scheme?.lowercased(),
      ["http", "https"].contains(scheme), let host = sourceURL.host, !host.isEmpty,
      sourceURL.user == nil, sourceURL.password == nil
    else { throw LegacyDownloadMigrationError.invalidItem(index: index, reason: .unsafeURL) }
    guard let consoleType = item.consoleType?.trimmingCharacters(in: .whitespacesAndNewlines),
      !consoleType.isEmpty
    else { throw LegacyDownloadMigrationError.invalidItem(index: index, reason: .missingConsole) }

    let fileType = item.fileType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let fileExtension = extensionFor(fileType: fileType, sourceURL: sourceURL)
    let titleID = item.titleId?.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedTitleID = titleID?.isEmpty == false ? titleID : nil
    let recordedTitle = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    let title =
      recordedTitle?.isEmpty == false
      ? recordedTitle! : sourceURL.deletingPathExtension().lastPathComponent
    guard !title.isEmpty else {
      throw LegacyDownloadMigrationError.invalidItem(index: index, reason: .missingName)
    }

    if let recordedDestination = item.destinationURL, !recordedDestination.isFileURL {
      throw LegacyDownloadMigrationError.invalidItem(index: index, reason: .nonLocalDestination)
    }
    let safeConsole = DownloadCoordinator.safePathComponent(consoleType)
    let destinationDirectory =
      item.destinationURL?.deletingLastPathComponent()
      ?? destinationRoot.appendingPathComponent(safeConsole, isDirectory: true)
    let destinationURL =
      item.destinationURL
      ?? nextAvailableURL(
        title: title,
        fileExtension: fileExtension,
        in: destinationDirectory,
        occupiedPaths: &occupiedPaths
      )
    occupiedPaths.insert(destinationURL.path)

    let request = DownloadJobRequest(
      sourceURL: sourceURL,
      title: title,
      consoleType: consoleType,
      titleID: normalizedTitleID,
      fileExtension: fileExtension,
      // An old queue entry does not contain a trustworthy snapshot of its
      // extraction settings. Keep the archive intact after an explicit resume.
      extractAfterDownload: false,
      zrif: item.zrif?.isEmpty == false ? item.zrif : nil
    )
    let status = item.status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let completedStatuses: Set<String> = [
      "download complete", "extraction complete", "missing zrif, license not created",
    ]
    let normalizedStatus = status.lowercased()
    let isExtractionComplete = normalizedStatus == "extraction complete"
    let extractedDirectoryURL =
      isExtractionComplete
      ? archivedPSVOutputDirectory(
        consoleType: consoleType,
        fileType: fileType,
        titleID: normalizedTitleID,
        destinationURL: item.destinationURL
      ) : nil
    let isComplete =
      completedStatuses.contains(normalizedStatus) || (status.isEmpty && item.isViewable == true)
    let extractionLocationError: LocalizedMessage? =
      if isExtractionComplete && extractedDirectoryURL == nil {
        LocalizedMessage(DownloadSnapshot.legacyOutputLocationUnknownKey)
      } else if isExtractionComplete, let extractedDirectoryURL,
        !isDirectory(at: extractedDirectoryURL)
      { DownloadSnapshot.legacyOutputLocationMissingMessage(for: extractedDirectoryURL) } else {
        nil
      }
    let usableResumeData = item.resumeData.flatMap { $0.isEmpty ? nil : $0 }
    let state: DownloadState
    let errorMessage: LocalizedMessage?
    let resumeData: Data?
    let progress: Double
    let bytesReceived: Int64
    if isComplete {
      state = .complete
      errorMessage = extractionLocationError
      resumeData = nil
      progress = 1
      bytesReceived = 0
    } else if status.lowercased().hasPrefix("failed") {
      state = .failed
      errorMessage = LocalizedMessage("error.migration.legacyFailed", .text(status))
      resumeData = nil
      progress = normalizedProgress(item.progress)
      bytesReceived = 0
    } else if let usableResumeData {
      state = .paused
      errorMessage = LocalizedMessage("error.migration.legacyResumePreserved")
      resumeData = usableResumeData
      progress = normalizedProgress(item.progress)
      // The old format stores a percentage, not a byte count. A nonzero
      // marker prevents a missing-resume fallback from looking like a fresh job.
      bytesReceived = 1
    } else {
      state = .failed
      errorMessage = LocalizedMessage("error.migration.legacyInterruptedWithoutResume")
      resumeData = nil
      progress = normalizedProgress(item.progress)
      bytesReceived = 0
    }

    let libraryRoot = destinationDirectory.deletingLastPathComponent()
    let volumeUUID = try? libraryRoot.resourceValues(forKeys: [.volumeUUIDStringKey])
      .volumeUUIDString
    var migrated = PersistedDownload(
      id: stableID(for: item, index: index),
      request: request,
      state: state,
      progress: progress,
      bytesReceived: bytesReceived,
      destinationDirectory: destinationDirectory,
      destinationVolumeUUID: volumeUUID,
      destinationURL: destinationURL,
      verifiedPackage: false,
      compatibilityPatchDestinationURL: nil,
      compatibilityPatchVerified: false,
      activeTransfer: .primary,
      extractedDirectoryURL: extractedDirectoryURL,
      legacyOutputLocationUnknown: isExtractionComplete && extractedDirectoryURL == nil,
      errorMessage: nil,
      resumeData: resumeData,
      createdAt: now,
      updatedAt: now
    )
    migrated.setError(errorMessage)
    return migrated
  }

  private static func stableID(for item: LegacyDownloadItem, index: Int) -> UUID {
    let fields = [
      String(index), item.titleId ?? "", item.name ?? "", item.downloadUrl?.absoluteString ?? "",
      item.status ?? "", item.destinationURL?.absoluteString ?? "", item.consoleType ?? "",
      item.fileType ?? "", item.resumeData.map(fingerprint) ?? "",
    ]
    let digest = Array(SHA256.hash(data: Data(fields.joined(separator: "\u{1f}").utf8)).prefix(16))
    let groups = [digest[0..<4], digest[4..<6], digest[6..<8], digest[8..<10], digest[10..<16]]
    let uuid = groups.map { group in group.map { String(format: "%02X", $0) }.joined() }.joined(
      separator: "-"
    )
    return UUID(uuidString: uuid)!
  }

  static func fingerprint(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func backupRaw(_ data: Data, in directory: URL) throws {
    let digest = fingerprint(data)
    let backupURL = directory.appendingPathComponent("downloads-legacy-\(digest).plist")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: backupURL.path) {
        guard try Data(contentsOf: backupURL) == data else {
          throw CocoaError(.fileWriteFileExists)
        }
        return
      }
      try data.write(to: backupURL, options: .atomic)
    } catch { throw LegacyDownloadMigrationError.backupFailed(error.localizedDescription) }
  }
}

private struct LegacyDownloadList: Decodable { let items: [LegacyDownloadItem] }

/// The archived app's `DLItem.CodingKeys`. Only value fields needed by the new
/// queue are decoded; transient request/UI state and nested CPack references are ignored.
/// The old CPack→CPatch setup linked `doNext` to the patch and `parentItem` back
/// to the pack. Synthesized Codable encodes those as nested values, so that cycle
/// could not be represented in its binary plist.
private struct LegacyDownloadItem: Decodable {
  let titleId: String?
  let name: String?
  let downloadUrl: URL?
  let progress: Double?
  let zrif: String?
  let status: String?
  let resumeData: Data?
  let destinationURL: URL?
  let isViewable: Bool?
  let consoleType: String?
  let fileType: String?

  private enum CodingKeys: String, CodingKey {
    case titleId
    case name
    case downloadUrl
    case progress
    case zrif
    case status
    case resumeData
    case destinationURL
    case isViewable
    case consoleType
    case fileType
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    titleId = try values.decodeIfPresent(String.self, forKey: .titleId)
    name = try values.decodeIfPresent(String.self, forKey: .name)
    downloadUrl = try values.decodeIfPresent(URL.self, forKey: .downloadUrl)
    progress = try values.decodeIfPresent(Double.self, forKey: .progress)
    zrif = try values.decodeIfPresent(String.self, forKey: .zrif)
    status = try values.decodeIfPresent(String.self, forKey: .status)
    resumeData = try values.decodeIfPresent(Data.self, forKey: .resumeData)
    destinationURL = try values.decodeIfPresent(URL.self, forKey: .destinationURL)
    isViewable = try values.decodeIfPresent(Bool.self, forKey: .isViewable)
    consoleType = try values.decodeIfPresent(String.self, forKey: .consoleType)
    fileType = try values.decodeIfPresent(String.self, forKey: .fileType)
  }
}
