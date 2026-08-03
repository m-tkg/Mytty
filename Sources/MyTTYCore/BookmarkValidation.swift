import Foundation

/// Pure decision logic for whether a line bookmark should be dropped, kept
/// out of `TerminalBookmarkCoordinator` (MyTTYApp) so it can be tested
/// without faking a Ghostty surface.
///
/// A bookmark tracks a Ghostty pin that auto-follows its line as the
/// scrollback is edited, and is relocated to the screen's top-left (row 0,
/// column 0) once the line it pointed to is fully evicted from
/// scrollback (see `PageList.trackPin`'s documented behavior). That
/// relocation is what `createdRow != 0` detects below; a bookmark
/// legitimately created at row 0 is never mistaken for one that has been
/// evicted to row 0, since the two are only distinguished by whether the
/// row actually changed.
public enum BookmarkValidation {
    /// - Parameters:
    ///   - createdRow: The row the bookmark pin resolved to when created.
    ///   - currentRow: The row the pin currently resolves to.
    ///   - currentX: The column the pin currently resolves to.
    ///   - screenIsActive: Whether the primary screen is the surface's
    ///     active screen right now. While an alternate-screen program
    ///     (a pager, a TUI) is active, the primary screen isn't being
    ///     mutated, so a bookmark can't have been evicted — keep it.
    ///   - textMatches: Whether the line's current text still matches the
    ///     bookmark's stored snapshot (both trimmed).
    /// - Returns: `true` when the bookmark should be removed.
    public static func shouldRemove(
        createdRow: Int,
        currentRow: Int,
        currentX: Int,
        screenIsActive: Bool,
        textMatches: Bool
    ) -> Bool {
        guard screenIsActive else { return false }
        if currentRow == 0, currentX == 0, createdRow != 0 { return true }
        return !textMatches
    }
}
