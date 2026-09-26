import Foundation

/// Owns the non-Sendable NotificationCenter observer tokens outside the
/// main-actor controller so cleanup is safe from Swift's nonisolated `deinit`.
final class WorkspaceNotificationSubscriptions: @unchecked Sendable {
  private let center: NotificationCenter
  private var observers: [NSObjectProtocol] = []

  init(center: NotificationCenter) { self.center = center }

  func start(names: [Notification.Name], handler: @escaping @Sendable (Notification) -> Void) {
    guard observers.isEmpty else { return }
    observers = names.map { name in
      center.addObserver(forName: name, object: nil, queue: .main, using: handler)
    }
  }

  func stop() {
    observers.forEach(center.removeObserver)
    observers.removeAll()
  }

  deinit { stop() }
}
