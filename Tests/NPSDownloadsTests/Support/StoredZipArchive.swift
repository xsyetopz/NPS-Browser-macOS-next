import Foundation

struct StoredZipEntry {
  let name: String
  let data: Data
  var mode: UInt32 = 0x81A4
}

private let crc32Table: [UInt32] = (0..<256).map { index in
  var value = UInt32(index)
  for _ in 0..<8 { value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB88320 : value >> 1 }
  return value
}

func storedZip(_ entries: [StoredZipEntry], comment: Data = Data()) -> Data {
  var archive = Data()
  var central = Data()
  for entry in entries {
    let name = Data(entry.name.utf8)
    let checksum = crc32(entry.data)
    let offset = UInt32(archive.count)
    archive.appendLE32(0x04034b50)
    archive.appendLE16(20)
    archive.appendLE16(0)
    archive.appendLE16(0)
    archive.appendLE16(0)
    archive.appendLE16(0)
    archive.appendLE32(checksum)
    archive.appendLE32(UInt32(entry.data.count))
    archive.appendLE32(UInt32(entry.data.count))
    archive.appendLE16(UInt16(name.count))
    archive.appendLE16(0)
    archive.append(name)
    archive.append(entry.data)

    central.appendLE32(0x02014b50)
    central.appendLE16(UInt16((3 << 8) | 20))
    central.appendLE16(20)
    central.appendLE16(0)
    central.appendLE16(0)
    central.appendLE16(0)
    central.appendLE16(0)
    central.appendLE32(checksum)
    central.appendLE32(UInt32(entry.data.count))
    central.appendLE32(UInt32(entry.data.count))
    central.appendLE16(UInt16(name.count))
    central.appendLE16(0)
    central.appendLE16(0)
    central.appendLE16(0)
    central.appendLE16(0)
    central.appendLE32(entry.mode << 16)
    central.appendLE32(offset)
    central.append(name)
  }
  let centralOffset = UInt32(archive.count)
  archive.append(central)
  archive.appendLE32(0x06054b50)
  archive.appendLE16(0)
  archive.appendLE16(0)
  archive.appendLE16(UInt16(entries.count))
  archive.appendLE16(UInt16(entries.count))
  archive.appendLE32(UInt32(central.count))
  archive.appendLE32(centralOffset)
  archive.appendLE16(UInt16(comment.count))
  archive.append(comment)
  return archive
}

private func crc32(_ data: Data) -> UInt32 {
  var crc: UInt32 = 0xFFFFFFFF
  for byte in data {
    let index = Int((crc ^ UInt32(byte)) & 0xFF)
    crc = (crc >> 8) ^ crc32Table[index]
  }
  return ~crc
}

private extension Data {
  mutating func appendLE16(_ value: UInt16) {
    append(UInt8(value & 0xFF))
    append(UInt8((value >> 8) & 0xFF))
  }

  mutating func appendLE32(_ value: UInt32) {
    appendLE16(UInt16(value & 0xFFFF))
    appendLE16(UInt16((value >> 16) & 0xFFFF))
  }
}
