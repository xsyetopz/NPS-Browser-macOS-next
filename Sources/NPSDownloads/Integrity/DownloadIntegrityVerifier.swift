import CryptoKit
import Foundation
import NPSCore

enum DownloadIntegrityVerifier {
  static func validate(
    _ completion: TransferCompletion,
    for request: DownloadJobRequest
  ) throws -> VerifiedDownload {
    do {
      let response = completion.response
      guard (200..<300).contains(response.statusCode) else {
        throw DownloadValidationError.httpStatus(response.statusCode)
      }

      if let mimeType = response.mimeType?.lowercased() {
        let type =
          mimeType.split(separator: ";", maxSplits: 1).first.map(String.init)?.trimmingCharacters(
            in: .whitespaces
          ) ?? mimeType
        if type.hasPrefix("text/")
          || ["application/xml", "text/xml", "application/xhtml+xml", "application/json"].contains(
            type
          )
        {
          throw DownloadValidationError.invalidContentType(type)
        }
      }

      let values = try completion.temporaryURL.resourceValues(forKeys: [.fileSizeKey])
      let actualLength = Int64(values.fileSize ?? 0)
      guard actualLength > 0 else {
        throw DownloadValidationError.lengthMismatch(
          expected: request.expectedByteCount ?? 1,
          actual: actualLength
        )
      }
      if let expected = request.expectedByteCount, expected != actualLength {
        throw DownloadValidationError.lengthMismatch(expected: expected, actual: actualLength)
      }
      if response.expectedContentLength > 0 && response.statusCode != 206
        && response.expectedContentLength != actualLength
      {
        throw DownloadValidationError.lengthMismatch(
          expected: response.expectedContentLength,
          actual: actualLength
        )
      }

      let prefix = try readPrefix(at: completion.temporaryURL, count: 1024)
      if looksLikeMarkup(prefix) { throw DownloadValidationError.errorDocument }
      if request.fileExtension.lowercased() == "pkg" {
        let header = try readPrefix(at: completion.temporaryURL, count: 256)
        try validatePKGHeader(header, actualLength: actualLength, fileURL: completion.temporaryURL)
      } else if request.fileExtension.lowercased() == "ppk" {
        let signature = try readPrefix(at: completion.temporaryURL, count: 4)
        guard signature == Data([0x50, 0x4B, 0x03, 0x04]) else {
          throw DownloadValidationError.invalidCompatibilityHeader
        }
      } else if request.fileExtension.lowercased() == "rap", actualLength != 16 {
        throw DownloadValidationError.invalidRAPPayload
      }

      let digest = try hashFile(at: completion.temporaryURL)
      if let expected = request.sha256?.lowercased(), expected != digest {
        throw DownloadValidationError.hashMismatch(expected: expected, actual: digest)
      }
      return VerifiedDownload(
        temporaryURL: completion.temporaryURL,
        byteCount: actualLength,
        sha256: digest
      )
    } catch {
      try? FileManager.default.removeItem(at: completion.temporaryURL)
      throw error
    }
  }

  static func install(_ verified: VerifiedDownload, at destinationURL: URL) throws -> URL {
    let fileManager = FileManager.default
    do {
      try fileManager.createDirectory(
        at: destinationURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      guard !fileManager.fileExists(atPath: destinationURL.path) else {
        throw CocoaError(.fileWriteFileExists)
      }

      // Stage on the destination volume. Moving this verified copy to the
      // visible filename is atomic even if the library is on another volume.
      let staged = destinationURL.deletingLastPathComponent().appendingPathComponent(
        ".\(UUID().uuidString).verified-part"
      )
      do {
        try fileManager.copyItem(at: verified.temporaryURL, to: staged)
        try fileManager.moveItem(at: staged, to: destinationURL)
      } catch {
        try? fileManager.removeItem(at: staged)
        throw error
      }
      try? fileManager.removeItem(at: verified.temporaryURL)
      return destinationURL
    } catch { throw DownloadValidationError.destinationUnavailable(LocalizedMessage(error)) }
  }

  private static func readPrefix(at url: URL, count: Int) throws -> Data {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    return file.readData(ofLength: count)
  }

  private static func looksLikeMarkup(_ data: Data) -> Bool {
    guard let sample = String(data: data, encoding: .utf8)?.lowercased() else { return false }
    let trimmed = sample.trimmingCharacters(
      in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}"))
    )
    if trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<!doctype html")
      || trimmed.hasPrefix("<html")
    {
      return true
    }
    guard trimmed.first == "<" else { return false }

    // Short server error documents may use arbitrary XML roots (for example
    // `<error>`) and still have the exact byte count expected of a RAP file.
    let parser = XMLParser(data: Data(trimmed.utf8))
    parser.shouldResolveExternalEntities = false
    return parser.parse()
  }

  private static func hashFile(at url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var hasher = SHA256()
    while true {
      let chunk = file.readData(ofLength: 1024 * 1024)
      guard !chunk.isEmpty else { break }
      hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func validatePKGHeader(_ header: Data, actualLength: Int64, fileURL: URL) throws {
    guard header.count == 256 else { throw DownloadValidationError.invalidPackageHeader(.tooShort) }
    guard header.prefix(4) == Data([0x7f, 0x50, 0x4b, 0x47]) else {
      throw DownloadValidationError.invalidPackageHeader(.missingSignature)
    }
    guard header.subdata(in: 192..<196) == Data([0x7f, 0x65, 0x78, 0x74]) else {
      throw DownloadValidationError.invalidPackageHeader(.missingExtendedSignature)
    }

    let fileLength = UInt64(actualLength)
    let metadataOffset = UInt64(readUInt32BE(header, at: 8))
    let metadataCount = UInt64(readUInt32BE(header, at: 12))
    let itemCount = UInt64(readUInt32BE(header, at: 20))
    let declaredLength = readUInt64BE(header, at: 24)
    let encryptedOffset = readUInt64BE(header, at: 32)
    let encryptedSize = readUInt64BE(header, at: 40)
    let keyType = header[0xE7] & 0x07

    guard declaredLength >= 256, declaredLength <= fileLength else {
      throw DownloadValidationError.invalidPackageHeader(.lengthOutsideFile)
    }
    guard (1...4).contains(keyType) else {
      throw DownloadValidationError.invalidPackageHeader(.unsupportedKeyType)
    }
    guard metadataCount >= 2, metadataOffset >= 256, metadataOffset < encryptedOffset,
      encryptedOffset <= declaredLength
    else { throw DownloadValidationError.invalidPackageHeader(.inconsistentOffsets) }
    guard itemCount > 0, itemCount <= (declaredLength - encryptedOffset) / 32,
      encryptedSize >= itemCount * 32, encryptedSize <= declaredLength - encryptedOffset
    else { throw DownloadValidationError.invalidPackageHeader(.itemTableOutsidePackage) }

    guard metadataCount <= (encryptedOffset - metadataOffset) / 8, metadataCount <= 1_000_000 else {
      throw DownloadValidationError.invalidPackageHeader(.metadataCountExceedsRegion)
    }

    let file = try FileHandle(forReadingFrom: fileURL)
    defer { try? file.close() }
    var offset = metadataOffset
    var itemTableOffset: UInt64?
    var itemTableSize: UInt64?
    var contentTypeFound = false
    for _ in 0..<metadataCount {
      guard offset <= encryptedOffset, encryptedOffset - offset >= 8 else {
        throw DownloadValidationError.invalidPackageHeader(.metadataBeyondBoundary)
      }
      try file.seek(toOffset: offset)
      let metadataHeader = file.readData(ofLength: 8)
      guard metadataHeader.count == 8 else {
        throw DownloadValidationError.invalidPackageHeader(.metadataEntryTruncated)
      }
      let type = readUInt32BE(metadataHeader, at: 0)
      let size = UInt64(readUInt32BE(metadataHeader, at: 4))
      guard size <= encryptedOffset - offset - 8 else {
        throw DownloadValidationError.invalidPackageHeader(.metadataEntryExceedsRegion)
      }
      if type == 2 {
        guard size >= 4 else {
          throw DownloadValidationError.invalidPackageHeader(.contentTypeTruncated)
        }
        contentTypeFound = true
      } else if type == 13 {
        guard size >= 8 else {
          throw DownloadValidationError.invalidPackageHeader(.itemTableTruncated)
        }
        let itemData = file.readData(ofLength: 8)
        guard itemData.count == 8 else {
          throw DownloadValidationError.invalidPackageHeader(.itemTableTruncated)
        }
        itemTableOffset = UInt64(readUInt32BE(itemData, at: 0))
        itemTableSize = UInt64(readUInt32BE(itemData, at: 4))
      }
      offset += 8 + size
    }
    guard contentTypeFound, let itemTableOffset, let itemTableSize, itemTableSize >= itemCount * 32,
      itemTableOffset <= encryptedSize, itemTableSize <= encryptedSize - itemTableOffset
    else { throw DownloadValidationError.invalidPackageHeader(.itemTableMissing) }
  }

  private static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
    (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16)
      | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
  }

  private static func readUInt64BE(_ data: Data, at offset: Int) -> UInt64 {
    (UInt64(readUInt32BE(data, at: offset)) << 32) | UInt64(readUInt32BE(data, at: offset + 4))
  }
}
