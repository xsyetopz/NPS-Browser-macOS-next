import Foundation

public protocol PackageExtractor: Sendable {
  func extract(
    packageURL: URL,
    request: DownloadJobRequest,
    destinationDirectory: URL
  ) async throws -> URL
}
