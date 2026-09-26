import Foundation
import NPSCore

enum CompatibilityPackArchive {
  private static let maxEntries: UInt32 = 60_000
  private static let maxExpandedSize: UInt64 = 50 * 1024 * 1024 * 1024
  private static let maxPathComponentsPerEntry = 256
  private static let maxPathComponentsTotal = 1_000_000

  static func validate(_ url: URL) throws {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let size = UInt64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    guard size >= 22 else { throw invalid("error.archive.reason.missingEndRecord") }
    let tailSize = Int(min(size, 65_557))
    let tailOffset = size - UInt64(tailSize)
    let tail = try read(file, tailOffset, tailSize)
    guard let endIndex = findEOCD(tail) else {
      throw invalid("error.archive.reason.missingEndRecord")
    }
    let eocd = tail.subdata(in: endIndex..<(endIndex + 22))
    guard UInt64(endIndex) + 22 + UInt64(u16(eocd, 20)) == UInt64(tail.count) else {
      throw invalid("error.archive.reason.invalidCommentLength")
    }

    let count = UInt32(u16(eocd, 10))
    let cdSize = UInt64(u32(eocd, 12))
    let cdOffset = UInt64(u32(eocd, 16))
    let eocdOffset = tailOffset + UInt64(endIndex)
    guard u16(eocd, 4) == 0, u16(eocd, 6) == 0, u16(eocd, 8) == u16(eocd, 10), count > 0,
      count <= maxEntries, u32(eocd, 12) != UInt32.max, u32(eocd, 16) != UInt32.max,
      cdOffset <= eocdOffset, cdSize <= eocdOffset - cdOffset
    else { throw invalid("error.archive.reason.unsupportedArchive") }

    let cdEnd = cdOffset + cdSize
    var cursor = cdOffset
    var paths: [String: Bool] = [:]
    var descendantCounts: [String: Int] = [:]
    var regularFiles = 0
    var expanded: UInt64 = 0
    var totalPathComponents = 0
    for _ in 0..<count {
      guard cursor <= cdEnd, cdEnd - cursor >= 46 else {
        throw invalid("error.archive.reason.centralEntryTruncated")
      }
      let h = try read(file, cursor, 46)
      guard u32(h, 0) == 0x02014b50 else {
        throw invalid("error.archive.reason.invalidCentralSignature")
      }
      let madeBy = u16(h, 4)
      let flags = u16(h, 8)
      let method = u16(h, 10)
      let compressed = UInt64(u32(h, 20))
      let uncompressed = UInt64(u32(h, 24))
      let nameLength = Int(u16(h, 28))
      let variableLength = UInt64(nameLength + Int(u16(h, 30)) + Int(u16(h, 32)))
      let localOffset = UInt64(u32(h, 42))
      guard u16(h, 34) == 0, u32(h, 20) != UInt32.max, u32(h, 24) != UInt32.max,
        u32(h, 42) != UInt32.max, variableLength <= cdEnd - cursor - 46
      else { throw invalid("error.archive.reason.unsupportedEntry") }
      guard flags & 1 == 0, method == 0 || method == 8 else {
        throw invalid("error.archive.reason.unsupportedCompression")
      }

      let rawName = try read(file, cursor + 46, nameLength)
      guard let name = String(data: rawName, encoding: .utf8) else {
        throw invalid("error.archive.reason.invalidName")
      }
      let attributes = u32(h, 38)
      let unix = madeBy >> 8 == 3
      let unixType = unix ? (attributes >> 28) & 0xF : 0
      let hasMode = unix && ((attributes >> 16) & 0xF000 != 0)
      guard !hasMode || unixType == 0x8 || unixType == 0x4 else {
        throw unsafe(name, "error.archive.reason.specialFile")
      }
      let directory = name.hasSuffix("/") || attributes & 0x10 != 0 || unixType == 0x4
      let parts = try safeComponents(name, directory: directory)
      totalPathComponents += parts.count
      guard totalPathComponents <= maxPathComponentsTotal else {
        throw invalid("error.archive.reason.tooManyComponents")
      }
      try register(name, parts, directory, &paths, &descendantCounts)
      if !directory { regularFiles += 1 }

      guard localOffset <= cdOffset, cdOffset - localOffset >= 30 else {
        throw invalid("error.archive.reason.localHeaderOutOfBounds")
      }
      let local = try read(file, localOffset, 30)
      let localNameLength = Int(u16(local, 26))
      let dataOffset = localOffset + 30 + UInt64(localNameLength) + UInt64(u16(local, 28))
      guard u32(local, 0) == 0x04034b50, u16(local, 6) & 1 == 0, u16(local, 8) == method,
        localNameLength == nameLength, dataOffset <= cdOffset, compressed <= cdOffset - dataOffset,
        try read(file, localOffset + 30, localNameLength) == rawName
      else { throw invalid("error.archive.reason.headersDisagree") }
      guard expanded <= maxExpandedSize, uncompressed <= maxExpandedSize - expanded else {
        throw invalid("error.archive.reason.sizeLimit")
      }
      expanded += uncompressed
      cursor += 46 + variableLength
    }
    guard cursor == cdEnd, regularFiles > 0 else {
      throw invalid("error.archive.reason.inconsistentDirectory")
    }
  }

  private static func findEOCD(_ data: Data) -> Int? {
    guard data.count >= 22 else { return nil }
    for i in stride(from: data.count - 22, through: 0, by: -1) where u32(data, i) == 0x06054b50 {
      let commentLength = Int(u16(data, i + 20))
      if i + 22 + commentLength == data.count { return i }
    }
    return nil
  }

  private static func safeComponents(_ name: String, directory: Bool) throws -> [String] {
    let path = directory && name.hasSuffix("/") ? String(name.dropLast()) : name
    guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("\\") else {
      throw unsafe(name, "error.archive.reason.absolutePath")
    }
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
      parts.count <= maxPathComponentsPerEntry,
      !path.unicodeScalars.contains(where: {
        $0 == "\\" || $0 == ":" || CharacterSet.controlCharacters.contains($0)
      })
    else { throw unsafe(name, "error.archive.reason.unsafePath") }
    return parts
  }

  private static func register(
    _ name: String,
    _ parts: [String],
    _ directory: Bool,
    _ paths: inout [String: Bool],
    _ descendantCounts: inout [String: Int]
  ) throws {
    let normalized = parts.map {
      $0.precomposedStringWithCanonicalMapping.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
    }
    let key = normalized.joined(separator: "/")
    for i in 1..<normalized.count where paths[normalized.prefix(i).joined(separator: "/")] == false
    { throw unsafe(name, "error.archive.reason.parentIsFile") }
    guard paths[key] == nil else { throw unsafe(name, "error.archive.reason.duplicatePath") }
    if !directory, descendantCounts[key, default: 0] > 0 {
      throw unsafe(name, "error.archive.reason.fileConflictsWithChild")
    }
    paths[key] = directory
    for i in 1..<normalized.count {
      descendantCounts[normalized.prefix(i).joined(separator: "/"), default: 0] += 1
    }
  }

  private static func read(_ file: FileHandle, _ offset: UInt64, _ count: Int) throws -> Data {
    try file.seek(toOffset: offset)
    let data = file.readData(ofLength: count)
    guard data.count == count else { throw invalid("error.archive.reason.truncated") }
    return data
  }

  private static func u16(_ d: Data, _ i: Int) -> UInt16 { UInt16(d[i]) | UInt16(d[i + 1]) << 8 }
  private static func u32(_ d: Data, _ i: Int) -> UInt32 {
    UInt32(u16(d, i)) | UInt32(u16(d, i + 2)) << 16
  }
  /// `reasonKey` names an `error.archive.reason.*` catalog entry.
  static func invalid(_ reasonKey: String) -> CompatibilityPackArchiveError {
    .invalidArchive(LocalizedMessage(reasonKey))
  }
  static func unsafe(_ name: String, _ reasonKey: String) -> CompatibilityPackArchiveError {
    .unsafeEntry(name, LocalizedMessage(reasonKey))
  }
}
