import AppKit
import NPSBrowserAppResources

extension BrowserViewController {
  private struct BookmarkSelectionContext {
    let entryID: String
    let selectionRevision: UInt64
    let contextRevision: UInt64
    let section: BrowserSection
  }

  @objc
  func toggleBookmark(_ sender: Any?) {
    guard section != .downloads, let entry = catalogueController.selectedEntry else { return }
    toggleBookmark(for: entry)
  }

  func toggleBookmark(for entry: BrowserEntry) {
    guard section != .downloads else { return }
    guard !entry.isCompatibilityPack else {
      showError(AppResources.localized("compatibility.bookmarkNotice"))
      return
    }
    let shouldBookmark = !bookmarkedIDs.contains(entry.id)
    let selectionContext: BookmarkSelectionContext?
    if !shouldBookmark, section == .bookmarks, catalogueController.selectedEntry?.id == entry.id {
      selectionContext = BookmarkSelectionContext(
        entryID: entry.id,
        selectionRevision: catalogueSelectionRevision,
        contextRevision: bookmarkContextRevision,
        section: section
      )
    } else {
      selectionContext = nil
    }

    // Update the inspector and visible state before persistence completes.
    let pendingWrite = bookmarkWrites.beginWrite(entry.id, isBookmarked: shouldBookmark)
    catalogueController.setBookmarks(bookmarkedIDs)
    let selectedEntry = catalogueController.selectedEntry
    inspectorController.show(
      entry: selectedEntry,
      bookmarked: selectedEntry.map { bookmarkedIDs.contains($0.id) } ?? false
    )
    validateVisibleToolbarItems()

    let generation = pendingWrite.generation
    let precedingWrite = pendingWrite.precedingWrite
    let write = Task { [weak self] in
      guard let self else { return }
      await precedingWrite?.value
      do {
        try await dataSource.setBookmarked(entry, isBookmarked: shouldBookmark)
        bookmarkWrites.confirmWrite(entry.id, isBookmarked: shouldBookmark, generation: generation)
      } catch {
        // Only the newest intent owns the final UI state. Earlier
        // failures must not undo a later optimistic toggle.
        guard bookmarkWrites.isCurrent(generation, for: entry.id) else { return }
        let persistedIDs = try? await dataSource.loadBookmarkedIDs()
        guard bookmarkWrites.isCurrent(generation, for: entry.id) else { return }
        bookmarkWrites.rollBack(entry.id, persistedIDs: persistedIDs, generation: generation)
        catalogueController.setBookmarks(bookmarkedIDs)
        restoreBookmarkSelectionIfAppropriate(selectionContext)
        updateInspectorForCurrentSelection()
        showError(error.localizedDescription)
      }
    }
    bookmarkWrites.track(write, for: entry.id)
  }

  private func updateInspectorForCurrentSelection() {
    let selectedEntry = catalogueController.selectedEntry
    inspectorController.show(
      entry: selectedEntry,
      bookmarked: selectedEntry.map { bookmarkedIDs.contains($0.id) } ?? false
    )
    validateVisibleToolbarItems()
  }

  private func restoreBookmarkSelectionIfAppropriate(_ context: BookmarkSelectionContext?) {
    guard let context, context.section == .bookmarks, section == context.section,
      catalogueSelectionRevision == context.selectionRevision,
      bookmarkContextRevision == context.contextRevision, catalogueController.selectedEntry == nil
    else { return }
    catalogueController.selectEntry(withID: context.entryID)
  }
}
