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

        // Cap the line count before aligning/stripping so every later
        // index (cursorRow, styled re-segmentation) lines up with the
        // capped array. Neither wrap stripping nor styled re-segmentation
        // changes the line count, so this order is safe and makes both of
        // them cheaper too.
        if lines.count > maxLines {
            let dropped = lines.count - maxLines
            lines.removeFirst(dropped)
            if let row = cursorRow {
                cursorRow = max(row - dropped, 0)
            }
        }

        // Re-segment the VT read's physical (wrap-broken) rows back into
        // plain's logical rows *before* stripping wrap padding: padding
        // removal needs the same character offsets applied to both plain
        // and styled text, which only lines up once each styled row
        // corresponds to exactly one plain line (see `alignStyledLines`).
        var styled = alignStyledLines(styledLines, toPlainLines: lines)

        // Strip wrap-padding spaces line by line, after the cursor's raw
        // row/column are pinned (they're computed from the same padded
        // text on both sides, so the subtraction above stays exact).
        // Styled lines carry the same padding (the VT read doesn't strip
        // it either), so the same offsets are applied to both, keeping
        // `styled[i].plainText == lines[i]` intact.
        if gridColumns > 0 {
            let styledOffset = lines.count - styled.count
            for index in lines.indices {
                let padding = wrapPaddingIndices(
                    in: lines[index],
                    columns: gridColumns
                )
                if index == cursorRow, let rawColumn = cursorColumn,
                    !padding.isEmpty {
                    let droppedBefore = padding.count { $0 < rawColumn }
                    cursorColumn = max(rawColumn - droppedBefore, 0)
                }
                if !padding.isEmpty {
                    lines[index] = removingCharacters(
                        padding,
                        from: lines[index]
                    )
                }

                let styledIndex = index - styledOffset
                guard styledIndex >= 0, styledIndex < styled.count else {
                    continue
                }
                let strippedStyled = padding.isEmpty
                    ? styled[styledIndex]
                    : styled[styledIndex].removingCharacters(at: padding)
                if strippedStyled.plainText == lines[index] {
                    styled[styledIndex] = strippedStyled
                } else {
                    // The styled row no longer mirrors the plain row it's
                    // supposed to match (version skew, or a bug upstream).
                    // Fall back to one uncolored span rather than send
                    // mismatched cells — text and cursor position are the
                    // contract, color is decoration. A single non-empty
                    // span (not zero spans) matters for older clients that
                    // don't guard against a length mismatch themselves:
                    // an empty-spans line renders as blank there.
                    styled[styledIndex] = RemoteStyledLine(
                        spans: [RemoteTextSpan(text: lines[index])]
                    )
                }
            }
        }

        return withinContentBudget(
            RemotePaneContent(
                text: lines.joined(separator: "\n"),
                cursorRow: cursorRow,
                cursorColumn: cursorColumn,
                styledLines: styled,
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
            // Styled lines are bottom-aligned to `lines`; dropping from
            // the front of one without the other would leave
            // `styledLines.count > lines.count`, which sends the client a
            // negative `styledOffset`.
            if !content.styledLines.isEmpty {
                content.styledLines.removeFirst(
                    min(drop, content.styledLines.count)
                )
            }
        }
        return content
    }

    /// Re-segments the VT read's physical (wrap-broken) rows back into
    /// `plainLines`' logical rows (soft wraps joined), matching from the
    /// bottom of the screen upward.
    ///
    /// The two reads split lines differently: the plain read unwraps soft
    /// wraps into one logical line, the VT read emits one physical row per
    /// wrap. Bottom-aligning row-for-row (the old behavior) silently
    /// desyncs the moment any line above the match point has wrapped, so
    /// every row from there up ends up matched against the wrong plain
    /// line. Re-segmenting by content sidesteps that: physical rows are
    /// greedily consumed and concatenated until they equal one logical
    /// line exactly, so the result is aligned by construction rather than
    /// by position.
    ///
    /// Any divergence — a character mismatch, running out of physical
    /// rows, or a physical row overrunning past the end of the logical
    /// line it's being matched against — stops the walk there; everything
    /// from that point upward (older) is left uncolored rather than
    /// guessed at.
    static func alignStyledLines(
        _ styledRows: [RemoteStyledLine],
        toPlainLines plainLines: [String],
        maxBytes: Int = maxStyledBytes
    ) -> [RemoteStyledLine] {
        guard !styledRows.isEmpty, !plainLines.isEmpty else { return [] }

        // The VT read can carry extra trailing blank physical rows beyond
        // what the plain read ended with. Drop them — but only while the
        // plain side doesn't itself end on a blank line, since a single
        // soft-wrapped logical line spans several physical rows and would
        // otherwise look identical to a real trailing blank and get eaten
        // by mistake.
        var styled = styledRows
        while let lastStyled = styled.last,
            lastStyled.plainText.trimmingCharacters(in: .whitespaces)
                .isEmpty,
            let lastPlain = plainLines.last,
            !lastPlain.trimmingCharacters(in: .whitespaces).isEmpty {
            styled.removeLast()
        }

        var result: [RemoteStyledLine?] = Array(
            repeating: nil,
            count: plainLines.count
        )
        var styledCursor = styled.count

        outer: for plainIndex in stride(
            from: plainLines.count - 1,
            through: 0,
            by: -1
        ) {
            guard styledCursor > 0 else { break }
            let plainChars = Array(plainLines[plainIndex])
            // Counts down from the last character of this logical line as
            // physical rows are matched against it back to front; -1 means
            // every character has been accounted for.
            var plainCursor = plainChars.count - 1
            // Rows are appended as they're consumed (newest/bottom-most
            // first) and reversed once at the end, rather than inserted at
            // the front each time, so a single long wrapped line doesn't
            // cost O(rows²).
            var consumedNewestFirst: [RemoteStyledLine] = []
            var isFirstRow = true

            while isFirstRow || plainCursor >= 0 {
                // A blank logical line still consumes exactly one physical
                // row, so the loop always runs once even when
                // `plainCursor` starts at -1 already.
                guard styledCursor > 0 else { break outer }
                styledCursor -= 1
                let row = styled[styledCursor]
                let rowChars = Array(row.plainText)
                consumedNewestFirst.append(row)
                isFirstRow = false

                var rowCursor = rowChars.count - 1
                while rowCursor >= 0 {
                    guard plainCursor >= 0,
                        rowChars[rowCursor] == plainChars[plainCursor]
                    else {
                        // Either this physical row has more characters
                        // than remain in the logical line (overrun), or a
                        // character differs outright. Either way the rest
                        // of the screen is unreliable to match, so stop
                        // entirely rather than guess.
                        break outer
                    }
                    plainCursor -= 1
                    rowCursor -= 1
                }
            }

            let joined = RemoteStyledLine.joining(
                consumedNewestFirst.reversed()
            )
            // Belt-and-suspenders: the character walk above already
            // guarantees equality, but re-check the assembled strings in
            // case joining spans across a row boundary ever shifts a
            // grapheme cluster boundary (e.g. a combining mark ghostty
            // split across two physical rows). A mismatch here stops the
            // walk the same way a character mismatch does.
            guard joined.plainText == plainLines[plainIndex] else {
                break outer
            }
            result[plainIndex] = joined
        }

        // `result` only ever has a contiguous run of `nil`s at the front
        // (everything from the first divergence upward): the loop above
        // breaks out entirely on any mismatch instead of leaving a hole
        // mid-array, so dropping the nils can't misalign the surviving
        // entries with the plain lines they follow from the bottom.
        return withinByteBudget(result.compactMap { $0 }, maxBytes: maxBytes)
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

    /// Finds the wrap-padding spaces a line editor (zsh's ZLE, TUIs) writes
    /// into a row's last column when a wide character doesn't fit there and
    /// wraps to the next row instead. That space is invisible on the host
    /// — it sits at the row's right edge, past where the cursor wraps —
    /// but ghostty's `unwrap=true` read joins the soft-wrapped rows into
    /// one logical line, so the space lands mid-line, and the remote
    /// client then re-wraps that logical line at its own width, making the
    /// space visible where it never was on the host.
    ///
    /// This works by re-simulating the same column-filling ghostty's own
    /// terminal emulation did to lay the logical line out over rows in the
    /// first place, so it can tell a genuine row boundary (and any padding
    /// space sitting on one) apart from a space that is just ordinary
    /// text. A space only counts as padding when it sits in the last
    /// column of a simulated row *and* the next character is wide: a
    /// narrow character there would have fit in that same last column, so
    /// a space in front of it is real content, not padding.
    ///
    /// Returns ascending, duplicate-free Character offsets into `line` —
    /// the same contract `RemoteStyledLine.removingCharacters(at:)`
    /// expects, so a caller can apply the identical offsets to a styled
    /// line aligned to this plain line and keep both in character sync.
    static func wrapPaddingIndices(in line: String, columns: Int) -> [Int] {
        // A line whose maximum possible display width (every character
        // wide) still fits in one row cannot have wrapped, so it cannot
        // contain padding — skip the walk entirely.
        guard columns >= 2, line.count * 2 > columns else { return [] }

        let characters = Array(line)
        var droppedIndices: [Int] = []
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
                    droppedIndices.append(index)
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
        return droppedIndices
    }

    /// Convenience wrapper over `wrapPaddingIndices(in:columns:)` for plain
    /// text, also remapping a raw Character column past the removed
    /// padding. Kept as its own entry point so the (still substantial)
    /// existing test coverage for wrap-padding stripping needs no changes.
    static func strippingWrapPadding(
        _ line: String,
        columns: Int,
        rawColumn: Int? = nil
    ) -> (text: String, column: Int?) {
        let droppedIndices = wrapPaddingIndices(in: line, columns: columns)
        guard !droppedIndices.isEmpty else { return (line, rawColumn) }

        let text = removingCharacters(droppedIndices, from: line)

        let column: Int?
        if let rawColumn {
            let droppedBefore = droppedIndices.count { $0 < rawColumn }
            column = max(rawColumn - droppedBefore, 0)
        } else {
            column = nil
        }
        return (text, column)
    }

    /// Removes the characters at `offsets` (ascending, duplicate-free
    /// Character indices) from `line`. The plain-text counterpart to
    /// `RemoteStyledLine.removingCharacters(at:)`, so the same offset list
    /// can be applied to both and keep them character-aligned.
    private static func removingCharacters(
        _ offsets: [Int],
        from line: String
    ) -> String {
        guard !offsets.isEmpty else { return line }
        let offsetSet = Set(offsets)
        var text = ""
        text.reserveCapacity(line.count)
        for (position, character) in line.enumerated()
        where !offsetSet.contains(position) {
            text.append(character)
        }
        return text
    }
}
