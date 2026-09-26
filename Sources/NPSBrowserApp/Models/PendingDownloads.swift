import Foundation
import NPSBrowserAppResources

struct PendingDownloads {
  struct PendingEnqueue {
    let jobID: UUID
    let entry: DownloadEntry
  }

  private var pendingEnqueues: [String: PendingEnqueue] = [:]

  @discardableResult
  mutating func add(key: String, jobID: UUID, placeholder: DownloadEntry) -> Bool {
    guard pendingEnqueues[key] == nil else { return false }
    pendingEnqueues[key] = PendingEnqueue(jobID: jobID, entry: placeholder)
    return true
  }

  @discardableResult
  mutating func remove(key: String, jobID: UUID) -> Bool {
    guard pendingEnqueues[key]?.jobID == jobID else { return false }
    pendingEnqueues.removeValue(forKey: key)
    return true
  }

  mutating func resolve(against snapshot: [DownloadEntry]) {
    // A placeholder is replaced by exactly the job it requested, as soon as
    // any snapshot contains it, so the row neither disappears nor doubles.
    let persistedIDs = Set(snapshot.map(\.id))
    pendingEnqueues = pendingEnqueues.filter { !persistedIDs.contains($0.value.jobID.uuidString) }
  }

  func merged(with snapshot: [DownloadEntry]) -> [DownloadEntry] {
    snapshot + pendingEnqueues.values.map(\.entry)
  }
}

extension PendingDownloads {
  static func packageKey(for entry: BrowserEntry) -> String { entry.id }
  static func updateKey(for entry: BrowserEntry) -> String { "update-\(entry.id)" }
  static func rapKey(for entry: BrowserEntry) -> String { "rap-\(entry.id)" }

  static func packagePlaceholder(for entry: BrowserEntry) -> DownloadEntry {
    DownloadEntry(
      id: placeholderID(forKey: packageKey(for: entry)),
      title: entry.title,
      detail: entry.titleID,
      state: .queued,
      progress: 0,
      completedFile: nil,
      titleID: entry.titleID,
      canRemove: false
    )
  }

  static func updatePlaceholder(for entry: BrowserEntry) -> DownloadEntry {
    DownloadEntry(
      id: placeholderID(forKey: updateKey(for: entry)),
      title: DownloadTitle.update(for: entry),
      detail: AppResources.localized("status.checkingUpdate"),
      state: .queued,
      statusText: AppResources.localized("status.checkingUpdate"),
      progress: nil,
      completedFile: nil,
      titleID: entry.titleID,
      canRemove: false
    )
  }

  static func rapPlaceholder(for entry: BrowserEntry) -> DownloadEntry {
    DownloadEntry(
      id: placeholderID(forKey: rapKey(for: entry)),
      title: DownloadTitle.rap(for: entry),
      detail: entry.titleID,
      state: .queued,
      progress: 0,
      completedFile: nil,
      titleID: entry.titleID,
      canRemove: false
    )
  }

  private static func placeholderID(forKey key: String) -> String { "pending-\(key)" }
}
