import Foundation

/// One rendered character with its resolved style. `foreground`/
/// `background` are 0xRRGGBB, or nil for the client's default color, so
/// this stays platform-neutral — no `Color`/`UIColor` here.
public struct RemotePaneCell: Equatable, Sendable {
    public var character: Character
    public var foreground: Int?
    public var background: Int?
    public var bold: Bool
    public var faint: Bool
    public var inverse: Bool

    public init(
        character: Character,
        foreground: Int? = nil,
        background: Int? = nil,
        bold: Bool = false,
        faint: Bool = false,
        inverse: Bool = false
    ) {
        self.character = character
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.faint = faint
        self.inverse = inverse
    }

    fileprivate func hasSameStyle(as other: RemotePaneCell) -> Bool {
        foreground == other.foreground
            && background == other.background
            && bold == other.bold
            && faint == other.faint
            && inverse == other.inverse
    }
}

/// A run of consecutive cells that share the same style — the unit callers
/// turn into one styled text run (e.g. one `AttributedString` run).
public struct RemotePaneRun: Equatable, Sendable {
    public var text: String
    public var foreground: Int?
    public var background: Int?
    public var bold: Bool
    public var faint: Bool
    public var inverse: Bool
}

/// Turns a pane's plain text plus its per-cell styling (already resolved to
/// RGB by the Mac) into styled runs ready for display, with the cursor cell
/// rendered as an inverse block, like a terminal's block cursor.
///
/// Colored lines are bottom-aligned to the plain text: any leading plain
/// lines that have no corresponding styled line fall back to the client's
/// default color. Callers own turning `RemotePaneRun`s into their platform's
/// styled text type (e.g. mapping `foreground`/`background` to `Color`).
public enum RemotePaneScreenRenderer {
    /// Renders every line of a pane. Each element of the result is one
    /// line's styled runs, in display order; an empty array means a blank
    /// line.
    public static func renderedLines(
        text: String,
        cursorRow: Int?,
        cursorColumn: Int?,
        styledLines: [RemoteStyledLine]
    ) -> [[RemotePaneRun]] {
        var lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if let row = cursorRow {
            while lines.count <= row { lines.append("") }
        }

        // Colored lines are bottom-aligned to the plain lines.
        let styledOffset = lines.count - styledLines.count

        return lines.enumerated().map { index, line in
            var cells = cellsForLine(
                at: index,
                plain: line,
                styledOffset: styledOffset,
                styledLines: styledLines
            )
            if index == cursorRow, let column = cursorColumn {
                applyCursor(to: &cells, column: column)
            }
            return runs(from: cells)
        }
    }

    private static func cellsForLine(
        at index: Int,
        plain: String,
        styledOffset: Int,
        styledLines: [RemoteStyledLine]
    ) -> [RemotePaneCell] {
        let styledIndex = index - styledOffset
        guard styledIndex >= 0, styledIndex < styledLines.count else {
            return plain.map { RemotePaneCell(character: $0) }
        }
        var cells: [RemotePaneCell] = []
        for span in styledLines[styledIndex].spans {
            for character in span.text {
                cells.append(
                    RemotePaneCell(
                        character: character,
                        foreground: span.foreground,
                        background: span.background,
                        bold: span.bold,
                        faint: span.faint,
                        inverse: span.inverse
                    )
                )
            }
        }
        return cells
    }

    private static func applyCursor(
        to cells: inout [RemotePaneCell],
        column: Int
    ) {
        while cells.count <= column {
            cells.append(RemotePaneCell(character: " "))
        }
        cells[column].inverse.toggle()
    }

    /// Coalesces consecutive same-style cells into styled runs.
    private static func runs(from cells: [RemotePaneCell]) -> [RemotePaneRun] {
        var result: [RemotePaneRun] = []
        var runText = ""
        var runStyle: RemotePaneCell?

        func flush() {
            guard let style = runStyle, !runText.isEmpty else { return }
            result.append(
                RemotePaneRun(
                    text: runText,
                    foreground: style.foreground,
                    background: style.background,
                    bold: style.bold,
                    faint: style.faint,
                    inverse: style.inverse
                )
            )
            runText = ""
        }

        for cell in cells {
            if let style = runStyle, style.hasSameStyle(as: cell) {
                runText.append(cell.character)
            } else {
                flush()
                runStyle = cell
                runText = String(cell.character)
            }
        }
        flush()
        return result
    }
}
