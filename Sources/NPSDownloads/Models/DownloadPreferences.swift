import Foundation

/// A settings snapshot. The coordinator reads it when a job is enqueued and stores
/// the destination on that job, so later settings changes affect only new jobs.
public struct DownloadPreferences: Sendable {
  public let downloadDirectory: URL
  public let concurrentDownloads: Int

  public init(downloadDirectory: URL, concurrentDownloads: Int) {
    self.downloadDirectory = downloadDirectory
    self.concurrentDownloads = max(1, concurrentDownloads)
  }
}
