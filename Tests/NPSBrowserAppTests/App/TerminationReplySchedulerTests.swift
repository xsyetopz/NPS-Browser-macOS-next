import AppKit
import Testing
@testable import NPSBrowserApp

@MainActor
@Test(.sourceEnglish)
func terminationReplySchedulerRunsInAppKitModalRunLoopMode() {
  let probe = TerminationReplyProbe()

  TerminationReplyScheduler.schedule { probe.didRun = true }

  _ = RunLoop.current.run(mode: .modalPanel, before: Date(timeIntervalSinceNow: 0.1))

  #expect(probe.didRun)
}

@MainActor
private final class TerminationReplyProbe { var didRun = false }
