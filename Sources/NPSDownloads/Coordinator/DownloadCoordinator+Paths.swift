import Foundation

extension DownloadCoordinator {
  func nextAvailableURL(for request: DownloadJobRequest, in directory: URL) -> URL {
    nextAvailableURL(
      title: request.fileNameTitle,
      fileExtension: request.fileExtension,
      in: directory
    )
  }

  func nextAvailableURL(title: String, fileExtension: String, in directory: URL) -> URL {
    CollisionFreeFileURL.next(
      title: title,
      fileExtension: fileExtension,
      lowercasingExtension: true,
      in: directory,
      occupiedPaths: reservedPaths
    )
  }

  static func safePathComponent(_ input: String) -> String {
    let normalized = input.precomposedStringWithCanonicalMapping
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_()."))
    let value = String(normalized.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
      .trimmingCharacters(
        in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
      )
    if value.isEmpty || value == "." || value == ".." { return "Unknown" }
    return String(value.prefix(120))
  }

  static func safeFileName(_ input: String) -> String { safePathComponent(input) }
}
