import AppKit
import Foundation
import GhosttyAdapter
import MyTTYCore

/// A right-click "line bookmark" the user dropped on a pane's scrollback.
/// `handle` is the tracked Ghostty pin backing it — it auto-follows the
/// line's content as the scrollback changes, and must be released via
/// `GhosttySurfaceView.freeBookmark(_:)` once the bookmark is dropped
/// (see `TerminalBookmarkCoordinator.remove`/`removePane`).
struct PaneBookmark: Identifiable {
    let id = UUID()
    let handle: GhosttyBookmarkHandle
    /// The line's text as of bookmark creation (trimmed, or the localized
    /// empty-line placeholder). Every `validate(paneID:)` pass compares it
    /// against the live row to detect a line whose content has drifted
    /// out from under the pin.
    let snippet: String
    /// The row the pin resolved to when the bookmark was created. Used
    /// only to tell a legitimate row-0 bookmark apart from one that has
    /// been relocated to row 0 by eviction — see `BookmarkValidation`.
    let createdRow: Int
}

/// Owns per-pane line bookmarks: creating the underlying Ghostty pins,
/// listing them for the status bar, scrolling to one, and periodically
/// dropping any whose line has been evicted from scrollback or edited
/// out from under them. Modeled on `TerminalAutocompleteCoordinator` —
/// `TerminalWindowController` owns this and supplies live surface lookups
/// via a closure rather than this type reaching into it directly.
@MainActor
final class TerminalBookmarkCoordinator {
    private var bookmarksByPane: [TerminalSurfaceID: [PaneBookmark]] = [:]
    private var validationTimer: Timer?

    private let surface: (TerminalSurfaceID) -> GhosttySurfaceView?
    private var localizer: MyTTYLocalizer
    private let onChange: () -> Void

    init(
        surface: @escaping (TerminalSurfaceID) -> GhosttySurfaceView?,
        localizer: MyTTYLocalizer,
        onChange: @escaping () -> Void
    ) {
        self.surface = surface
        self.localizer = localizer
        self.onChange = onChange
    }

    func updateLocalizer(_ localizer: MyTTYLocalizer) {
        self.localizer = localizer
    }

    func bookmarks(for paneID: TerminalSurfaceID) -> [PaneBookmark] {
        bookmarksByPane[paneID] ?? []
    }

    /// Bookmarks the line at `location` (this pane's view coordinates,
    /// e.g. a right-click's location). No-op if the surface has no
    /// native handle or the click landed while the alternate screen is
    /// active — see `GhosttySurfaceView.createBookmark(atViewLocation:)`.
    func addBookmark(paneID: TerminalSurfaceID, location: NSPoint) {
        guard let surface = surface(paneID),
              let handle = surface.createBookmark(atViewLocation: location),
              let info = surface.bookmarkInfo(handle)
        else { return }
        let snippet = displaySnippet(
            for: surface.bookmarkLineText(handle) ?? ""
        )
        bookmarksByPane[paneID, default: []].append(
            PaneBookmark(handle: handle, snippet: snippet, createdRow: info.row)
        )
        scheduleValidationTimerIfNeeded()
        onChange()
    }

    func scrollTo(bookmarkID: PaneBookmark.ID, paneID: TerminalSurfaceID) {
        guard let surface = surface(paneID),
              let bookmark = bookmarksByPane[paneID]?
                  .first(where: { $0.id == bookmarkID })
        else { return }
        surface.scrollToBookmark(bookmark.handle)
    }

    func remove(bookmarkID: PaneBookmark.ID, paneID: TerminalSurfaceID) {
        guard var list = bookmarksByPane[paneID],
              let index = list.firstIndex(where: { $0.id == bookmarkID })
        else { return }
        let bookmark = list.remove(at: index)
        surface(paneID)?.freeBookmark(bookmark.handle)
        bookmarksByPane[paneID] = list.isEmpty ? nil : list
        stopValidationTimerIfIdle()
        onChange()
    }

    /// Releases every bookmark on a pane that is closing. If the surface
    /// is already gone, its pins went away with it — just drop the
    /// records rather than calling into a dead surface.
    func removePane(_ paneID: TerminalSurfaceID) {
        guard let list = bookmarksByPane.removeValue(forKey: paneID) else {
            return
        }
        if let surface = surface(paneID) {
            for bookmark in list {
                surface.freeBookmark(bookmark.handle)
            }
        }
        stopValidationTimerIfIdle()
        onChange()
    }

    /// Re-resolves every bookmark on `paneID` and drops the ones
    /// `BookmarkValidation` says should go: evicted from scrollback, or
    /// their line no longer reads the way it did when bookmarked. Cheap
    /// to call often — skips panes with no bookmarks and no-ops if the
    /// surface is gone (that pane's cleanup runs through `removePane`
    /// instead, once the pane actually closes).
    func validate(paneID: TerminalSurfaceID) {
        guard let surface = surface(paneID),
              let list = bookmarksByPane[paneID], !list.isEmpty
        else { return }

        var kept: [PaneBookmark] = []
        var removedAny = false
        for bookmark in list {
            guard let info = surface.bookmarkInfo(bookmark.handle) else {
                surface.freeBookmark(bookmark.handle)
                removedAny = true
                continue
            }
            let currentSnippet = displaySnippet(
                for: surface.bookmarkLineText(bookmark.handle) ?? ""
            )
            if BookmarkValidation.shouldRemove(
                createdRow: bookmark.createdRow,
                currentRow: info.row,
                currentX: info.x,
                screenIsActive: info.screenIsActive,
                textMatches: currentSnippet == bookmark.snippet
            ) {
                surface.freeBookmark(bookmark.handle)
                removedAny = true
            } else {
                kept.append(bookmark)
            }
        }
        bookmarksByPane[paneID] = kept.isEmpty ? nil : kept
        stopValidationTimerIfIdle()
        if removedAny { onChange() }
    }

    /// Validates every pane that currently has bookmarks. Driven by the
    /// background timer, since a bookmarked line in an unfocused pane can
    /// still scroll out of scrollback while nobody is looking at it.
    private func validateAll() {
        // Snapshot the keys first: `validate(paneID:)` mutates
        // `bookmarksByPane` as it goes, and iterating a dictionary's
        // `keys` view while mutating the same dictionary is unsafe.
        for paneID in Array(bookmarksByPane.keys) {
            validate(paneID: paneID)
        }
    }

    private func displaySnippet(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? localizer[.emptyLineBookmark] : trimmed
    }

    private func scheduleValidationTimerIfNeeded() {
        guard validationTimer == nil else { return }
        let timer = Timer(
            timeInterval: 5,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.validateAll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        validationTimer = timer
    }

    private func stopValidationTimerIfIdle() {
        guard bookmarksByPane.isEmpty else { return }
        validationTimer?.invalidate()
        validationTimer = nil
    }
}
