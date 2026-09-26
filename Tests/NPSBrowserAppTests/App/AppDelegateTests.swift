import AppKit
import Testing
@testable import NPSBrowserApp

@MainActor
@Test(.sourceEnglish)
func pauseFailureCancelsTerminationAndPresentsActionableMessage() {
  let delegate = AppDelegate(dataSource: ShutdownFailureBrowserDataSource())
  let probe = ShutdownFailureProbe()
  delegate.terminationReplyHandler = { probe.shouldTerminate = $0 }
  delegate.terminationFailurePresenter = { probe.message = $0 }

  // NSApplication.shared, not NSApp: NSApp stays nil until something creates
  // the application, which depends on which tests ran first.
  #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
  let deadline = Date(timeIntervalSinceNow: 5)
  while probe.shouldTerminate == nil, Date() < deadline {
    _ = RunLoop.current.run(mode: .modalPanel, before: Date(timeIntervalSinceNow: 0.05))
  }

  #expect(probe.shouldTerminate == false)
  #expect(
    probe.message?.localizedCaseInsensitiveContains("download queue could not be saved") == true
  )
  #expect(probe.message?.localizedCaseInsensitiveContains("write permissions") == true)
}

@MainActor
private final class ShutdownFailureProbe {
  var shouldTerminate: Bool?
  var message: String?
}
