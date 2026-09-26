import AppKit

@MainActor
final class BrowserContentViewController: NSViewController {
  private var contentViewController: NSViewController?

  override func loadView() {
    let root = NSView()
    root.translatesAutoresizingMaskIntoConstraints = false
    view = root
  }

  func show(_ controller: NSViewController) {
    guard contentViewController !== controller else { return }
    if let oldController = contentViewController {
      oldController.view.removeFromSuperview()
      oldController.removeFromParent()
    }

    contentViewController = controller
    addChild(controller)
    let childView = controller.view
    childView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(childView)
    NSLayoutConstraint.activate([
      childView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      childView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      childView.topAnchor.constraint(equalTo: view.topAnchor),
      childView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }
}
