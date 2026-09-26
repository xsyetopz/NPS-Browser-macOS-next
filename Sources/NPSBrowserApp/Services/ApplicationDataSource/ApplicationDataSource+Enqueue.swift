import Foundation
import NPSCore
import NPSDownloads

extension ApplicationDataSource {
  func enqueue(_ entry: BrowserEntry, jobID: UUID) async throws {
    guard let url = entry.packageURL else {
      throw CatalogueRefreshError.itemUnavailable(
        LocalizedMessage("error.enqueue.noPackageURL", .text(entry.title))
      )
    }
    if entry.compatibilityPackKind == .pack {
      let request = try Self.compatibilityPackRequest(
        for: entry,
        extractAfterDownload: settings.snapshot().extraction.extractAfterDownload
      )
      _ = try await downloads.enqueueCompatibilityPack(request, jobID: jobID)
      return
    }
    if entry.compatibilityPackKind == .patch {
      if entry.matchingPackURL != nil {
        let request = try Self.compatibilityPackRequest(
          for: entry,
          extractAfterDownload: settings.snapshot().extraction.extractAfterDownload
        )
        _ = try await downloads.enqueueCompatibilityPack(request, jobID: jobID)
      } else {
        try await enqueuePackage(
          jobID: jobID,
          sourceURL: url,
          entry: entry,
          title: entry.title,
          expectedByteCount: nil,
          sha256: nil,
          zrif: nil,
          fileExtension: "ppk",
          extractAfterDownload: settings.snapshot().extraction.extractAfterDownload,
          compatibilityPatchMode: .overlayExistingOutput
        )
      }
      return
    }
    let zrif = try await catalogue.allItems().first { $0.id == entry.id }?.zrif
    try await enqueuePackage(
      jobID: jobID,
      sourceURL: url,
      entry: entry,
      title: entry.title,
      expectedByteCount: entry.fileSize,
      sha256: entry.sha256,
      zrif: zrif,
      fileExtension: entry.isCompatibilityPack ? "ppk" : "pkg"
    )
  }

  func enqueueRAP(_ entry: BrowserEntry, jobID: UUID) async throws {
    guard entry.supportsRAPDownload, let url = entry.rapDownloadURL else {
      throw CatalogueRefreshError.itemUnavailable(LocalizedMessage("error.enqueue.invalidRAP"))
    }
    let request = DownloadJobRequest(
      sourceURL: url,
      title: DownloadTitle.rap(for: entry),
      consoleType: ConsoleType.PS3.rawValue,
      titleID: entry.titleID,
      fileExtension: "rap",
      // RAP files are license data, not packages; never send them to pkg2zip.
      extractAfterDownload: false,
      fileTitle: DownloadTitle.rapFileTitle(for: entry)
    )
    _ = try await downloads.enqueue(request, jobID: jobID)
  }

  static func compatibilityPackRequest(
    for entry: BrowserEntry,
    extractAfterDownload: Bool = true
  ) throws -> CompatibilityPackRequest {
    guard let kind = entry.compatibilityPackKind, !entry.titleID.isEmpty, entry.titleID != "—"
    else {
      throw CatalogueRefreshError.itemUnavailable(
        LocalizedMessage("error.enqueue.compatibilityTitleID")
      )
    }
    let packURL: URL
    let patchURL: URL?
    switch kind {
    case .pack:
      guard let url = entry.packageURL else {
        throw CatalogueRefreshError.itemUnavailable(
          LocalizedMessage("error.enqueue.compatibilityPackageURL")
        )
      }
      packURL = url
      patchURL = entry.compatibilityPatchURL
    case .patch:
      guard let url = entry.packageURL, let matchingPackURL = entry.matchingPackURL else {
        throw CatalogueRefreshError.itemUnavailable(
          LocalizedMessage("error.enqueue.compatibilityPatchPack")
        )
      }
      packURL = matchingPackURL
      patchURL = url
    }
    return CompatibilityPackRequest(
      titleID: entry.titleID,
      title: entry.compatibilityPackKind == .patch
        ? (entry.matchingPackTitle ?? entry.title) : entry.title,
      packURL: packURL,
      patchURL: patchURL,
      extractAfterDownload: extractAfterDownload
    )
  }

  func enqueueUpdate(_ entry: BrowserEntry, jobID: UUID) async throws {
    guard entry.supportsUpdateDownload else {
      throw CatalogueRefreshError.itemUnavailable(
        LocalizedMessage("error.enqueue.updatesUnavailable")
      )
    }
    let updateXMLURL = try CatalogParser.updateXMLURL(for: entry.titleID)
    let xml = try await CatalogueTextLoader.fetchText(from: updateXMLURL)
    let packageURL = try CatalogParser.parseUpdateXML(xml)
    let zrif = try await catalogue.allItems().first { $0.id == entry.id }?.zrif
    try await enqueuePackage(
      jobID: jobID,
      sourceURL: packageURL,
      entry: entry,
      title: DownloadTitle.update(for: entry),
      fileTitle: DownloadTitle.updateFileTitle(for: entry),
      expectedByteCount: nil,
      sha256: nil,
      zrif: zrif,
      fileExtension: "pkg"
    )
  }

  private func enqueuePackage(
    jobID: UUID,
    sourceURL: URL,
    entry: BrowserEntry,
    title: String,
    fileTitle: String? = nil,
    expectedByteCount: Int64?,
    sha256: String?,
    zrif: String?,
    fileExtension: String,
    extractAfterDownload: Bool? = nil,
    compatibilityPatchMode: CompatibilityPatchMode? = nil
  ) async throws {
    let settings = settings.snapshot()
    let request = DownloadJobRequest(
      sourceURL: sourceURL,
      title: title,
      consoleType: entry.consoleCode.isEmpty ? entry.console : entry.consoleCode,
      titleID: entry.titleID,
      expectedByteCount: expectedByteCount,
      sha256: sha256,
      fileExtension: fileExtension,
      // Compatibility feed entries return through their dedicated
      // composite or standalone-PPK paths above.
      extractAfterDownload: extractAfterDownload
        ?? (settings.extraction.extractAfterDownload && !entry.isCompatibilityPack),
      zrif: zrif,
      extractionOptions: PackageExtractionOptions(
        keepPackage: settings.extraction.keepPackage,
        saveAsZip: settings.extraction.saveAsZip,
        createLicense: settings.extraction.createLicense,
        compressPSPISO: settings.extraction.compressPSPISO,
        compressionFactor: settings.extraction.compressionFactor
      ),
      compatibilityPatchMode: compatibilityPatchMode,
      fileTitle: fileTitle
    )
    _ = try await downloads.enqueue(request, jobID: jobID)
  }
}
