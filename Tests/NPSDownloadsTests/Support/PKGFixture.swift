import CryptoKit
import Foundation

func makePKGFixture(repetitions: Int) -> Data {
  let encryptedOffset = 320
  let length = encryptedOffset + 32 + repetitions * 1024
  var bytes = Data(repeating: 0, count: length)
  bytes.replaceSubrange(0..<4, with: [0x7f, 0x50, 0x4b, 0x47])
  bytes.replaceSubrange(192..<196, with: [0x7f, 0x65, 0x78, 0x74])
  bytes[0xE7] = 2
  storeUInt32(256, at: 8, in: &bytes)
  storeUInt32(2, at: 12, in: &bytes)
  storeUInt32(1, at: 20, in: &bytes)
  storeUInt64(UInt64(length), at: 24, in: &bytes)
  storeUInt64(UInt64(encryptedOffset), at: 32, in: &bytes)
  storeUInt64(UInt64(length - encryptedOffset), at: 40, in: &bytes)
  // type 2: package content type; type 13: offset and byte size of item table.
  storeUInt32(2, at: 256, in: &bytes)
  storeUInt32(4, at: 260, in: &bytes)
  storeUInt32(0x15, at: 264, in: &bytes)
  storeUInt32(13, at: 268, in: &bytes)
  storeUInt32(8, at: 272, in: &bytes)
  storeUInt32(0, at: 276, in: &bytes)
  storeUInt32(32, at: 280, in: &bytes)
  for index in (encryptedOffset + 32)..<bytes.count { bytes[index] = 0x5a }
  return bytes
}

func storeUInt32(_ value: UInt32, at offset: Int, in data: inout Data) {
  data[offset] = UInt8((value >> 24) & 0xff)
  data[offset + 1] = UInt8((value >> 16) & 0xff)
  data[offset + 2] = UInt8((value >> 8) & 0xff)
  data[offset + 3] = UInt8(value & 0xff)
}

func storeUInt64(_ value: UInt64, at offset: Int, in data: inout Data) {
  storeUInt32(UInt32(value >> 32), at: offset, in: &data)
  storeUInt32(UInt32(value & 0xffff_ffff), at: offset + 4, in: &data)
}

func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
