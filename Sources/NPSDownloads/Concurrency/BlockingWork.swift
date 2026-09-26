import Dispatch

/// Runs blocking work (process waits, file hashing and copying) on a GCD queue.
/// `Task.detached` would still occupy one of Swift's fixed number of cooperative
/// threads for the whole wait and can stall unrelated async work.
enum BlockingWork {
  static func run<Value: Sendable>(
    qos: DispatchQoS.QoSClass = .utility,
    _ body: @escaping @Sendable () throws -> Value
  ) async throws -> Value {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: qos).async { continuation.resume(with: Result { try body() }) }
    }
  }
}
