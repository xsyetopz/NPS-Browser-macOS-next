import Foundation

/// The standalone CPatch workflow overlays its archive onto an existing title
/// output instead of replacing that output with patch-only files.
public enum CompatibilityPatchMode: String, Codable, Hashable, Sendable {
  case overlayExistingOutput
}
