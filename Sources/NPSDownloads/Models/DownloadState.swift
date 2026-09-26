import Foundation

public enum DownloadState: String, Codable, Sendable {
  case queued
  case downloading
  case paused
  case failed
  case verifying
  case extracting
  case complete
}
