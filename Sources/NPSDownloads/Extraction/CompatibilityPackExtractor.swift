import Foundation

struct CompatibilityPackExtractor: Sendable {
  func extract(
    packURL: URL,
    patchURL: URL?,
    titleID: String,
    destinationDirectory: URL
  ) async throws -> URL {
    try await BlockingWork.run {
      try CompatibilityPackArchive.extract(
        packURL: packURL,
        patchURL: patchURL,
        titleID: titleID,
        into: destinationDirectory
      )
    }
  }

  func applyPatch(patchURL: URL, titleID: String, destinationDirectory: URL) async throws -> URL {
    try await BlockingWork.run {
      try CompatibilityPackArchive.applyPatch(
        patchURL,
        titleID: titleID,
        into: destinationDirectory
      )
    }
  }
}
