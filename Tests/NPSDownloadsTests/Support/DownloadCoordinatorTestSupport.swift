import Foundation
@testable import NPSDownloads

final class LockedPreferences: @unchecked Sendable {
  private let lock = NSLock()
  private var current: DownloadPreferences

  init(_ value: DownloadPreferences) { current = value }

  func snapshot() -> DownloadPreferences {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  func update(_ value: DownloadPreferences) {
    lock.lock()
    defer { lock.unlock() }
    current = value
  }
}

final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  func increment() -> Int {
    lock.lock()
    defer { lock.unlock() }
    value += 1
    return value
  }
  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
  var isEmpty: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value == 0
  }
}

enum TestFailure: Error { case timedOut(UUID) }

struct FixturePackageExtractor: PackageExtractor {
  func extract(
    packageURL: URL,
    request: DownloadJobRequest,
    destinationDirectory: URL
  ) throws -> URL {
    let identity = request.titleID ?? "Fixture"
    let folder = destinationDirectory.appendingPathComponent(
      "Extracted [\(identity)]",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("fixture content".utf8).write(to: folder.appendingPathComponent("content.txt"))
    return folder
  }
}

func makeCoordinator(
  destination: URL,
  persistence: URL,
  limit: Int = 1
) throws -> DownloadCoordinator {
  try DownloadCoordinator(
    preferences: {
      DownloadPreferences(downloadDirectory: destination, concurrentDownloads: limit)
    },
    persistenceURL: persistence,
    urlSessionConfiguration: .ephemeral
  )
}

extension DownloadCoordinatorTests {
  func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NPSDownloadsTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}

func waitForTerminal(_ coordinator: DownloadCoordinator, id: UUID) async throws -> DownloadSnapshot
{
  for _ in 0..<600 {
    if let snapshot = await coordinator.snapshots().first(where: { $0.id == id }),
      snapshot.state == .complete || snapshot.state == .failed
    {
      return snapshot
    }
    try await Task.sleep(nanoseconds: 25_000_000)
  }
  throw TestFailure.timedOut(id)
}

func waitForAllTerminal(
  _ coordinator: DownloadCoordinator,
  ids: [UUID]
) async throws -> [DownloadSnapshot] {
  for _ in 0..<600 {
    let snapshots = await coordinator.snapshots()
    let matching = ids.compactMap { id in snapshots.first { $0.id == id } }
    if matching.count == ids.count
      && matching.allSatisfy({ $0.state == .complete || $0.state == .failed })
    {
      return matching
    }
    try await Task.sleep(nanoseconds: 25_000_000)
  }
  throw TestFailure.timedOut(ids.first ?? UUID())
}
