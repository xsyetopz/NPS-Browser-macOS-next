import Foundation

func makeCompatibilityPatchDirectory() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "NPSCompatibilityPatch-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}
