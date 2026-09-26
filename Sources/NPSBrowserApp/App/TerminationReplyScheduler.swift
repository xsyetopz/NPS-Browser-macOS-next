import CoreFoundation
import Foundation

enum TerminationReplyScheduler {
  static func schedule(_ reply: @escaping @MainActor @Sendable () -> Void) {
    let mainRunLoop = CFRunLoopGetMain()
    let terminationMode = RunLoop.Mode.modalPanel.rawValue as CFString
    CFRunLoopPerformBlock(mainRunLoop, terminationMode) { MainActor.assumeIsolated { reply() } }
    CFRunLoopWakeUp(mainRunLoop)
  }
}
