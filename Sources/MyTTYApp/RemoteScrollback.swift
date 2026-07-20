import Foundation
import MyTTYRemoteKit

/// Builds the pane content sent to remote clients from the full screen
/// buffer (scrollback included), remapping the viewport-relative cursor
/// into that text and capping the line count so frames stay bounded.
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
        viewportText: String,
        viewportCursor: (row: Int, column: Int)?,
        gridColumns: Int,
        gridRows: Int = 0,
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
        if let viewportCursor, gridColumns > 0 {
            let viewportLines = viewportText
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            // The cursor's row is a *visual* grid row, but read-text
            // unwraps soft-wrapped rows into single logical lines, so
            // the two units diverge as soon as any viewport line wraps.
            // Walk the logical lines' visual heights to find which
            // logical line the cursor sits on, then anchor that line
            // from the bottom (while following output both texts come
            // from the same trimmed read, so their tails line up).
            let located = locate(
                visualRow: viewportCursor.row,
                in: viewportLines,
                columns: gridColumns
            )
            let rowsFromBottom = viewportLines.count - located.lineIndex
            cursorRow = max(lines.count - rowsFromBottom, 0)

            let lineText = located.lineIndex < viewportLines.count
                ? viewportLines[located.lineIndex]
                : ""
            let cellOffset = located.rowWithinLine * gridColumns
                + viewportCursor.column
            cursorColumn = characterIndex(
                forCellOffset: cellOffset,
                in: lineText
            )
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

    /// Finds the logical line containing a visual grid row, given that
    /// each logical line occupies `ceil(cells / columns)` visual rows.
    /// A visual row below every written line resolves past the end of
    /// `lines` (one logical row per unwritten visual row).
    private static func locate(
        visualRow: Int,
        in lines: [String],
        columns: Int
    ) -> (lineIndex: Int, rowWithinLine: Int) {
        var remaining = visualRow
        for (index, line) in lines.enumerated() {
            let height = visualHeight(of: line, columns: columns)
            if remaining < height {
                return (index, remaining)
            }
            remaining -= height
        }
        return (lines.count + remaining, 0)
    }

    static func visualHeight(of line: String, columns: Int) -> Int {
        let cells = displayCells(of: line)
        return max(1, (cells + columns - 1) / columns)
    }

    /// Converts a grid cell offset into a character index within the
    /// line, accounting for double-width (East Asian) characters. An
    /// offset past the line's end maps past its last character so the
    /// client pads with spaces.
    static func characterIndex(
        forCellOffset offset: Int,
        in line: String
    ) -> Int {
        var consumedCells = 0
        for (index, character) in line.enumerated() {
            let width = displayWidth(of: character)
            if consumedCells + width > offset {
                return index
            }
            consumedCells += width
        }
        return line.count + (offset - consumedCells)
    }

    static func displayCells(of line: String) -> Int {
        line.reduce(0) { $0 + displayWidth(of: $1) }
    }

    /// Simplified wcwidth: 2 cells for East Asian wide/fullwidth ranges
    /// and emoji, 1 otherwise. Close enough to libghostty's own width
    /// tables for cursor placement in everyday CJK/emoji content.
    private static func displayWidth(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 1 }
        switch scalar.value {
        case 0x1100...0x115F,
             0x2E80...0x303E,
             0x3041...0x33FF,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xA000...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE30...0xFE4F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x1F300...0x1FAFF,
             0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }
}
