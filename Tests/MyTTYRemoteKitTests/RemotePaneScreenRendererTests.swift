import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite
struct RemotePaneScreenRendererTests {
    @Test
    func plainTextWithoutStyledLinesFallsBackToDefaultColor() {
        let lines = RemotePaneScreenRenderer.renderedLines(
            text: "hello",
            cursorRow: nil,
            cursorColumn: nil,
            styledLines: []
        )
        #expect(lines.count == 1)
        #expect(
            lines[0] == [
                RemotePaneRun(
                    text: "hello",
                    foreground: nil,
                    background: nil,
                    bold: false,
                    faint: false,
                    inverse: false
                ),
            ]
        )
    }

    @Test
    func multipleLinesSplitOnNewline() {
        let lines = RemotePaneScreenRenderer.renderedLines(
            text: "foo\nbar",
            cursorRow: nil,
            cursorColumn: nil,
            styledLines: []
        )
        #expect(lines.count == 2)
        #expect(lines[0].map(\.text) == ["foo"])
        #expect(lines[1].map(\.text) == ["bar"])
    }

    @Test
    func styledLinesAreBottomAlignedToPlainText() {
        // Two plain lines, but only one styled line: the styled line
        // applies to the *last* plain line, and the first line falls back
        // to unstyled (matching the Mac only sending color for the tail of
        // the scrollback it captured).
        let styled = RemoteStyledLine(spans: [
            RemoteTextSpan(text: "bar", foreground: 0xFF0000),
        ])
        let lines = RemotePaneScreenRenderer.renderedLines(
            text: "foo\nbar",
            cursorRow: nil,
            cursorColumn: nil,
            styledLines: [styled]
        )
        #expect(lines.count == 2)
        #expect(
            lines[0] == [
                RemotePaneRun(
                    text: "foo",
                    foreground: nil,
                    background: nil,
                    bold: false,
                    faint: false,
                    inverse: false
                ),
            ]
        )
        #expect(
            lines[1] == [
                RemotePaneRun(
                    text: "bar",
                    foreground: 0xFF0000,
                    background: nil,
                    bold: false,
                    faint: false,
                    inverse: false
                ),
            ]
        )
    }

    @Test
    func coalescesConsecutiveSameStyleSpansAcrossSpanBoundaries() {
        // Two spans with identical style must still coalesce into one run,
        // matching the per-cell coalescing the terminal itself would do.
        let styled = RemoteStyledLine(spans: [
            RemoteTextSpan(text: "ab", foreground: 0x00FF00, bold: true),
            RemoteTextSpan(text: "cd", foreground: 0x00FF00, bold: true),
            RemoteTextSpan(text: "ef", foreground: nil),
        ])
        let lines = RemotePaneScreenRenderer.renderedLines(
            text: "abcdef",
            cursorRow: nil,
            cursorColumn: nil,
            styledLines: [styled]
        )
        #expect(lines[0].map(\.text) == ["abcd", "ef"])
        #expect(lines[0][0].foreground == 0x00FF00)
        #expect(lines[0][0].bold == true)
        #expect(lines[0][1].foreground == nil)
    }

    @Test
    func cursorTogglesInverseOnExistingCell() {
        let styled = RemoteStyledLine(spans: [
            RemoteTextSpan(text: "hi", foreground: 0x123456),
        ])
        let lines = RemotePaneScreenRenderer.renderedLines(
            text: "hi",
            cursorRow: 0,
            cursorColumn: 1,
            styledLines: [styled]
        )
        // "h" stays one run, "i" becomes its own inverted run.
        #expect(lines[0].map(\.text) == ["h", "i"])
        #expect(lines[0][1].inverse == true)
        #expect(lines[0][0].inverse == false)
    }

    @Test
    func cursorPastLineEndPadsWithSpaces() {
        let lines = RemotePaneScreenRenderer.renderedLines(
            text: "hi",
            cursorRow: 0,
            cursorColumn: 4,
            styledLines: []
        )
        // Padding spaces share the default unstyled style with "hi", so
        // they coalesce into one run; only the cursor cell is its own
        // (inverted) run.
        #expect(lines[0].map(\.text) == ["hi  ", " "])
        #expect(lines[0].last?.inverse == true)
    }

    @Test
    func cursorRowBeyondTextExtendsLineCount() {
        let lines = RemotePaneScreenRenderer.renderedLines(
            text: "only",
            cursorRow: 2,
            cursorColumn: 0,
            styledLines: []
        )
        #expect(lines.count == 3)
        #expect(lines[1] == [])
        #expect(lines[2].map(\.text) == [" "])
        #expect(lines[2][0].inverse == true)
    }

    @Test
    func doubleInverseFromCursorOnAlreadyInverseCellCancelsOut() {
        let styled = RemoteStyledLine(spans: [
            RemoteTextSpan(text: "x", inverse: true),
        ])
        let lines = RemotePaneScreenRenderer.renderedLines(
            text: "x",
            cursorRow: 0,
            cursorColumn: 0,
            styledLines: [styled]
        )
        #expect(lines[0][0].inverse == false)
    }

    @Test
    func emptyLineProducesNoRuns() {
        let lines = RemotePaneScreenRenderer.renderedLines(
            text: "",
            cursorRow: nil,
            cursorColumn: nil,
            styledLines: []
        )
        #expect(lines == [[]])
    }
}
