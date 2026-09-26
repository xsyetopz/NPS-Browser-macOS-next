import Foundation

struct BookmarkWriteLedger {
  private(set) var bookmarkedIDs: Set<String> = []
  private(set) var confirmedBookmarkedIDs: Set<String> = []
  private var bookmarkWriteGenerations: [String: UInt64] = [:]
  private var bookmarkWriteTasks: [String: Task<Void, Never>] = [:]

  struct Write {
    let generation: UInt64
    let precedingWrite: Task<Void, Never>?
  }

  mutating func reset(to ids: Set<String>) {
    bookmarkedIDs = ids
    confirmedBookmarkedIDs = ids
  }

  mutating func beginWrite(_ id: String, isBookmarked: Bool) -> Write {
    Self.setState(id, isBookmarked: isBookmarked, in: &bookmarkedIDs)
    let generation = (bookmarkWriteGenerations[id] ?? 0) &+ 1
    bookmarkWriteGenerations[id] = generation
    return Write(generation: generation, precedingWrite: bookmarkWriteTasks[id])
  }

  mutating func track(_ task: Task<Void, Never>, for id: String) { bookmarkWriteTasks[id] = task }

  func isCurrent(_ generation: UInt64, for id: String) -> Bool {
    bookmarkWriteGenerations[id] == generation
  }

  mutating func confirmWrite(_ id: String, isBookmarked: Bool, generation: UInt64) {
    Self.setState(id, isBookmarked: isBookmarked, in: &confirmedBookmarkedIDs)
    finishWrite(id, generation: generation)
  }

  mutating func rollBack(_ id: String, persistedIDs: Set<String>?, generation: UInt64) {
    let persistedState = persistedIDs?.contains(id) ?? confirmedBookmarkedIDs.contains(id)
    Self.setState(id, isBookmarked: persistedState, in: &confirmedBookmarkedIDs)
    Self.setState(id, isBookmarked: persistedState, in: &bookmarkedIDs)
    finishWrite(id, generation: generation)
  }

  private mutating func finishWrite(_ id: String, generation: UInt64) {
    if isCurrent(generation, for: id) { bookmarkWriteTasks.removeValue(forKey: id) }
  }

  private static func setState(_ id: String, isBookmarked: Bool, in identifiers: inout Set<String>)
  { if isBookmarked { identifiers.insert(id) } else { identifiers.remove(id) } }
}
