import Foundation
import MyTTYRemoteKit

/// Builds the pane content sent to remote clients from the full screen
/// buffer (scrollback included), anchoring the cursor into that text and
/// capping the line count so frames stay bounded.
///
/// The cursor's logical line is found by reading, from ghostty, the exact
/// text from the cursor's active-area cell (inclusive) to the active
/// area's bottom-right corner — the "cursor suffix". Ghostty trims trailing blank
/// *lines* the same way on both this read and the full-screen read used
/// for `text` (both go through the same unwrap + trim=false selection
/// semantics), so the suffix's line count anchors the cursor from the
/// bottom of `lines` with no wrap-height estimation or width tables: a
/// soft-wrapped logical line reads back as one line on both sides, so the
/// suffix's first line is always the tail of the same logical line the
/// cursor sits in, and character counts subtract cleanly.
enum RemoteScrollback {
    /// Keeps pushes and phone-side rendering manageable; the Mac's own
    /// scrollback can be effectively unbounded. The real bound on a frame
    /// is `maxContentBytes` — this only stops line splitting and styling
    /// from chewing through a pathologically long scrollback first.
    static let maxLines = 10_000

    /// Upper bound on the JSON size of the styled lines in one frame, so a
    /// pathologically colorful screen never exceeds the 1 MB wire frame
    /// limit (leaving room for the plain text and encryption overhead).
    /// Oldest colored lines are dropped first when over budget; they still
    /// render, just without color.
    static let maxStyledBytes = 512 * 1024

    /// Upper bound on the encoded size of the whole `RemotePaneContent`,
    /// keeping the sealed frame safely under the 1 MB wire limit. When
    /// over budget, colored lines are sacrificed first, then the oldest
    /// plain lines.
    static let maxContentBytes = 768 * 1024

    static func content(
        screenText: String,
        viewportTextFromCursor: String?,
        gridRows: Int = 0,
        gridColumns: Int = 0,
        styledLines: [RemoteStyledLine] = [],
        maxLines: Int = maxLines
    ) -> RemotePaneContent {
        var lines = screenText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        // A pane whose whole screen fits the grid has no scrollback to
        // mirror — either an alternate-screen TUI or a shell that has not
        // scrolled yet. Both render as a single screen on the phone, so
        // scroll gestures are forwarded to the terminal instead (a no-op
        // for the fresh shell, the TUI's own scrolling otherwise).
        let altScreen = gridRows > 0 && lines.count <= gridRows

        var cursorRow: Int?
        var cursorColumn: Int?
        if let suffix = viewportTextFromCursor {
            // An empty suffix means the cursor sits right after the last
            // character ghostty wrote — i.e. on the last line, since
            // trailing blank lines are trimmed. `split` on "" yields [""],
            // so rowsFromBottom is 1 with no special case needed.
            let suffixLines = suffix
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            let rowsFromBottom = suffixLines.count
            let row = max(lines.count - rowsFromBottom, 0)
            cursorRow = row

            // The suffix's first line is the tail of the cursor's logical
            // line (both reads unwrap soft wraps identically), so the
            // character count leading up to it is exactly the cursor's
            // column — no cell-width math required.
            let lineText = row < lines.count ? lines[row] : ""
            cursorColumn = max(lineText.count - suffixLines[0].count, 0)
        }

        // Strip wrap-padding spaces line by line, after the cursor's raw
        // row/column are pinned (they're computed from the same padded
        // text on both sides, so the subtraction above stays exact) but
        // before line-count capping, so indices still line up with
        // `cursorRow`.
        if gridColumns > 0 {
            for index in lines.indices {
                let rawColumn = index == cursorRow ? cursorColumn : nil
                let stripped = strippingWrapPadding(
                    lines[index],
                    columns: gridColumns,
                    rawColumn: rawColumn
                )
                lines[index] = stripped.text
                if index == cursorRow {
                    cursorColumn = stripped.column
                }
            }
        }

        if lines.count > maxLines {
            let dropped = lines.count - maxLines
            lines.removeFirst(dropped)
            if let row = cursorRow {
                cursorRow = max(row - dropped, 0)
            }
        }

        return withinContentBudget(
            RemotePaneContent(
                text: lines.joined(separator: "\n"),
                cursorRow: cursorRow,
                cursorColumn: cursorColumn,
                styledLines: alignStyledLines(
                    styledLines,
                    toPlainLineCount: lines.count
                ),
                altScreen: altScreen
            )
        )
    }

    /// Shrinks the content until its encoded size fits the frame budget:
    /// oldest colored lines go first (they still render, just without
    /// color), then the oldest plain lines with the cursor remapped.
    static func withinContentBudget(
        _ content: RemotePaneContent,
        maxBytes: Int = maxContentBytes
    ) -> RemotePaneContent {
        // Approximates the wire frame's JSON: the pane text and styled
        // lines dominate it, the rest of the envelope is tens of bytes.
        struct EncodedSizeProxy: Encodable {
            let text: String
            let styledLines: [RemoteStyledLine]
        }
        let encoder = JSONEncoder()
        func size(_ content: RemotePaneContent) -> Int {
            let proxy = EncodedSizeProxy(
                text: content.text,
                styledLines: content.styledLines
            )
            return (try? encoder.encode(proxy).count) ?? 0
        }
        var content = content
        while size(content) > maxBytes, !content.styledLines.isEmpty {
            let drop = max(1, content.styledLines.count / 4)
            content.styledLines.removeFirst(drop)
        }
        guard size(content) > maxBytes else { return content }
        var lines = content.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        while size(content) > maxBytes, lines.count > 1 {
            let drop = max(1, lines.count / 4)
            lines.removeFirst(drop)
            content.text = lines.joined(separator: "\n")
            if let row = content.cursorRow {
                content.cursorRow = max(row - drop, 0)
            }
        }
        return content
    }

    /// Bottom-aligns styled lines to the final plain text. The styled lines
    /// come from a separate VT read that can carry extra trailing blank
    /// lines, so those are dropped first; the result is then capped to the
    /// plain line count from the bottom. A shorter result means the top
    /// plain lines render without color, which the client bottom-aligns.
    static func alignStyledLines(
        _ styledLines: [RemoteStyledLine],
        toPlainLineCount lineCount: Int,
        maxBytes: Int = maxStyledBytes
    ) -> [RemoteStyledLine] {
        guard !styledLines.isEmpty, lineCount > 0 else { return [] }
        var styled = styledLines
        while styled.count > lineCount,
              styled.last?.plainText.trimmingCharacters(
                  in: .whitespaces
              ).isEmpty == true {
            styled.removeLast()
        }
        if styled.count > lineCount {
            styled = Array(styled.suffix(lineCount))
        }
        return withinByteBudget(styled, maxBytes: maxBytes)
    }

    /// Drops the oldest (top) colored lines until the encoded array fits the
    /// byte budget, keeping the most recent lines colored.
    private static func withinByteBudget(
        _ styled: [RemoteStyledLine],
        maxBytes: Int
    ) -> [RemoteStyledLine] {
        let encoder = JSONEncoder()
        func size(_ lines: [RemoteStyledLine]) -> Int {
            (try? encoder.encode(lines).count) ?? 0
        }
        var lines = styled
        while !lines.isEmpty, size(lines) > maxBytes {
            // Drop a proportional chunk to converge quickly on large frames.
            let drop = max(1, lines.count / 8)
            lines.removeFirst(drop)
        }
        return lines
    }

    /// Removes wrap-padding spaces a line editor (zsh's ZLE, TUIs) writes
    /// into a row's last column when a wide character doesn't fit there
    /// and wraps to the next row instead. That space is invisible on the
    /// host — it sits at the row's right edge, past where the cursor
    /// wraps — but ghostty's `unwrap=true` read joins the soft-wrapped
    /// rows into one logical line, so the space lands mid-line, and the
    /// remote client then re-wraps that logical line at its own width,
    /// making the space visible where it never was on the host.
    ///
    /// This works by re-simulating the same column-filling ghostty's own
    /// terminal emulation did to lay the logical line out over rows in
    /// the first place, so it can tell a genuine row boundary (and any
    /// padding space sitting on one) apart from a space that is just
    /// ordinary text. A space only counts as padding when it sits in the
    /// last column of a simulated row *and* the next character is wide:
    /// a narrow character there would have fit in that same last column,
    /// so a space in front of it is real content, not padding.
    static func strippingWrapPadding(
        _ line: String,
        columns: Int,
        rawColumn: Int? = nil
    ) -> (text: String, column: Int?) {
        // A line whose maximum possible display width (every character
        // wide) still fits in one row cannot have wrapped, so it cannot
        // contain padding — skip the walk entirely.
        guard columns >= 2, line.count * 2 > columns else {
            return (line, rawColumn)
        }

        let characters = Array(line)
        var droppedIndices = Set<Int>()
        var col = 0
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let width = RemoteCellWidth.displayWidth(of: character)

            // Zero-width scalars (combining marks, etc.) ride along with
            // the previous cell and never occupy a column of their own.
            if width == 0 {
                index += 1
                continue
            }

            if character == " ", col == columns - 1 {
                var lookahead = index + 1
                while lookahead < characters.count,
                    RemoteCellWidth.displayWidth(of: characters[lookahead])
                        == 0
                {
                    lookahead += 1
                }
                if lookahead < characters.count,
                    RemoteCellWidth.displayWidth(of: characters[lookahead])
                        == 2
                {
                    droppedIndices.insert(index)
                    col = 0
                    index += 1
                    continue
                }
            }

            // A character that doesn't fit in what's left of the row
            // wraps to the next one first — this models ghostty's own
            // auto-wrap (a spacer cell that contributes nothing to the
            // text), not editor-written padding.
            if col + width > columns {
                col = 0
            }
            col += width
            if col >= columns {
                col = 0
            }
            index += 1
        }

        guard !droppedIndices.isEmpty else { return (line, rawColumn) }

        var text = ""
        text.reserveCapacity(characters.count)
        for (position, character) in characters.enumerated()
        where !droppedIndices.contains(position) {
            text.append(character)
        }

        let column: Int?
        if let rawColumn {
            let droppedBefore = droppedIndices.count { $0 < rawColumn }
            column = max(rawColumn - droppedBefore, 0)
        } else {
            column = nil
        }
        return (text, column)
    }
}
