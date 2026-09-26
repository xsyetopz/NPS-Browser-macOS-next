import AppKit
import NPSBrowserAppResources
import Testing
@testable import NPSBrowserApp

@MainActor
@Test(.sourceEnglish)
func navigationTableAndGroupHeadingsExposeLocalizedAccessibilityLabels() throws {
  let controller = NavigationViewController()
  _ = controller.view
  let scrollView = try #require(controller.view.subviews.compactMap { $0 as? NSScrollView }.first)
  let table = try #require(scrollView.documentView as? NSTableView)
  #expect(table.accessibilityLabel() == AppResources.localized("navigation.accessibility.label"))

  var groupLabels: [String] = []
  for row in 0..<controller.numberOfRows(in: table)
  where controller.tableView(table, isGroupRow: row) {
    let heading = try #require(
      controller.tableView(table, viewFor: table.tableColumns.first, row: row) as? NSTextField
    )
    #expect(heading.isAccessibilityElement())
    #expect(heading.accessibilityRole() == NSAccessibility.Role.staticText)
    #expect(heading.accessibilityLabel() != nil)
    groupLabels.append(try #require(heading.accessibilityLabel()))
  }

  #expect(
    groupLabels == [
      AppResources.localized("section.library"), AppResources.localized("section.category"),
      AppResources.localized("section.activity"),
    ]
  )
}
