import Foundation

final class LockedPatchRequestFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var requested = false

  var wasRequested: Bool {
    lock.lock()
    defer { lock.unlock() }
    return requested
  }

  func markRequested() {
    lock.lock()
    requested = true
    lock.unlock()
  }
}

actor ValidationGate {
  private var held = false
  private var heldWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func hold() async {
    held = true
    heldWaiters.forEach { $0.resume() }
    heldWaiters.removeAll()
    await withCheckedContinuation { releaseContinuation = $0 }
  }

  func waitUntilHeld() async {
    guard !held else { return }
    await withCheckedContinuation { heldWaiters.append($0) }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}
