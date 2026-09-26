import AppKit
import NPSBrowserAppResources

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var windowController: BrowserWindowController?
  private var dataSource: (any BrowserDataSource)?
  var terminationReplyHandler: (@MainActor @Sendable (Bool) -> Void)?
  var terminationFailurePresenter: (@MainActor @Sendable (String) -> Void)?

  init(dataSource: (any BrowserDataSource)? = nil) {
    self.dataSource = dataSource
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let dataSource: any BrowserDataSource
    var startupError: String?
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      let usePreviewDataSource =
        arguments.contains("--ui-preview") || arguments.contains("--ui-preview-game")
      let usePreviewGame = arguments.contains("--ui-preview-game")
    #else
      let usePreviewDataSource = false
      let usePreviewGame = false
    #endif
    if usePreviewDataSource {
      // Render native empty or inspector states without opening a user Realm
      // or fetching catalogues.
      #if DEBUG
        let previewEntries =
          usePreviewGame
          ? [
            BrowserEntry(
              id: "preview-psv-game",
              title: "Preview PS Vita Game",
              titleID: "PCSA00007",
              console: "PS Vita",
              consoleCode: "PSV",
              category: "Game",
              region: "US",
              fileSize: 734_003_200,
              packageURL: URL(string: "https://example.test/preview.pkg"),
              sha256: nil,
              contentID: "UP0000-PCSA00007_00-EXAMPLE000000000"
            )
          ] : []
        dataSource = EmptyBrowserDataSource(previewEntries: previewEntries)
      #else
        dataSource = EmptyBrowserDataSource()
      #endif
    } else {
      do { dataSource = try ApplicationDataSource() } catch {
        dataSource = EmptyBrowserDataSource()
        startupError = error.localizedDescription
      }
    }
    self.dataSource = dataSource
    let controller = BrowserWindowController(dataSource: dataSource)
    windowController = controller
    buildMainMenu(target: controller.browserViewController)
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    if let startupError { controller.browserViewController.presentStartupError(startupError) }
    #if DEBUG
      if let captureArgument = ProcessInfo.processInfo.arguments.first(where: {
        $0.hasPrefix("--capture-ui=")
      }) {
        let outputPath = String(captureArgument.dropFirst("--capture-ui=".count))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          self.captureWindowContent(controller.window, to: URL(fileURLWithPath: outputPath))
          NSApp.terminate(nil)
        }
      }
    #endif
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let dataSource else { return .terminateNow }
    let replyHandler =
      terminationReplyHandler ?? { shouldTerminate in
        NSApp.reply(toApplicationShouldTerminate: shouldTerminate)
      }
    let failurePresenter =
      terminationFailurePresenter ?? { message in
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppResources.localized("error.title")
        alert.informativeText = message
        alert.addButton(withTitle: AppResources.localized("alert.ok"))
        _ = alert.runModal()
      }
    // AppKit enters NSModalPanelRunLoopMode after this method returns
    // .terminateLater. Do the async drain outside MainActor, then schedule
    // the reply in AppKit's modal-panel run-loop mode so it can run inside
    // that nested termination loop (including when terminate was called
    // from a main-queue callback).
    Task.detached {
      do {
        try await dataSource.pauseDownloads()
        TerminationReplyScheduler.schedule { replyHandler(true) }
      } catch {
        let message = error.localizedDescription
        TerminationReplyScheduler.schedule {
          failurePresenter(message)
          replyHandler(false)
        }
      }
    }
    return .terminateLater
  }
  #if DEBUG
    private func captureWindowContent(_ window: NSWindow?, to url: URL) {
      guard let contentView = window?.contentView, contentView.bounds.width > 0,
        contentView.bounds.height > 0,
        let image = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
      else { return }
      contentView.layoutSubtreeIfNeeded()
      contentView.cacheDisplay(in: contentView.bounds, to: image)
      guard let data = image.representation(using: .png, properties: [:]) else { return }
      try? data.write(to: url, options: .atomic)
    }
  #endif
}
