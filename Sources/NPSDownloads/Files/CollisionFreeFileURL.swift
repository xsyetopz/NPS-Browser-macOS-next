import Foundation

/// Picks `<title>.<ext>`, then `<title> (2).<ext>`, `<title> (3).<ext>`, … until
/// the path is neither occupied nor present on disk.
enum CollisionFreeFileURL {
  static func next(
    title: String,
    fileExtension: String,
    lowercasingExtension: Bool,
    in directory: URL,
    occupiedPaths: Set<String>
  ) -> URL {
    let basename = DownloadCoordinator.safePathComponent(title)
    let suffix = lowercasingExtension ? fileExtension.lowercased() : fileExtension
    var index = 1
    while true {
      let collisionMarker = index == 1 ? "" : " (\(index))"
      let filename = "\(basename)\(collisionMarker).\(suffix)"
      let candidate = directory.appendingPathComponent(filename, isDirectory: false)
      if !occupiedPaths.contains(candidate.path),
        !FileManager.default.fileExists(atPath: candidate.path)
      {
        return candidate
      }
      index += 1
    }
  }
}
