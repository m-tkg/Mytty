import Foundation
import Testing

@testable import MyTTYApp
import MyTTYRemoteKit

@Suite("Remote scrollback")
struct RemoteScrollbackTests {
    private func styled(_ text: String) -> RemoteStyledLine {
        RemoteStyledLine(spans: [RemoteTextSpan(text: text)])
    }

    @Test("bottom-aligns styled lines and drops trailing blanks")
    func bottomAlignsStyledLines() {
        // Styled read has extra trailing blank lines beyond the plain text.
        let styledLines = [
            styled("one"), styled("two"), styled("three"),
            RemoteStyledLine(spans: []), RemoteStyledLine(spans: []),
        ]
        let content = RemoteScrollback.content(
            screenText: "one\ntwo\nthree",
            viewportTextFromCursor: nil,
            styledLines: styledLines
        )
        #expect(content.styledLines.map(\.plainText) == ["one", "two", "three"])
    }

    @Test("keeps styled lines aligned to the newest lines after capping")
    func styledFollowsLineCap() {
        let plain = (1...10).map { "line-\($0)" }
        let styledLines = plain.map(styled)
        let content = RemoteScrollback.content(
            screenText: plain.joined(separator: "\n"),
            viewportTextFromCursor: "line-9\nline-10",
            styledLines: styledLines,
            maxLines: 4
        )
        #expect(
            content.styledLines.map(\.plainText)
                == ["line-7", "line-8", "line-9", "line-10"]
        )
    }

    @Test("drops the oldest colored lines to stay within the byte budget")
    func trimsStyledToByteBudget() {
        let bigSpan = RemoteTextSpan(
            text: String(repeating: "X", count: 100),
            foreground: 0x112233,
            background: 0x445566
        )
        let styledLines = (0..<50).map { _ in
            RemoteStyledLine(spans: [bigSpan])
        }
        let aligned = RemoteScrollback.alignStyledLines(
            styledLines,
            toPlainLineCount: 50,
            maxBytes: 2000
        )
        #expect(aligned.count < 50)
        #expect(!aligned.isEmpty)
        // The most recent line is always kept.
        #expect(aligned.last == styledLines.last)
    }
    @Test("shrinks over-budget content by dropping styled lines first")
    func contentBudgetDropsStyledFirst() {
        let lines = (1...100).map { "line-\($0)" }
        let content = RemotePaneContent(
            text: lines.joined(separator: "\n"),
            cursorRow: 99,
            cursorColumn: 0,
            styledLines: lines.map(styled)
        )
        let budgeted = RemoteScrollback.withinContentBudget(
            content,
            maxBytes: 2000
        )
        #expect(budgeted.styledLines.count < content.styledLines.count)
        // The plain text survives at full length while styled lines can
        // absorb the whole overage.
        #expect(budgeted.text == content.text)
        #expect(budgeted.cursorRow == 99)
    }

    @Test("shrinks over-budget content by dropping the oldest plain lines")
    func contentBudgetDropsOldestText() {
        let lines = (1...200).map { "plain-line-\($0)" }
        let content = RemotePaneContent(
            text: lines.joined(separator: "\n"),
            cursorRow: 199,
            cursorColumn: 0
        )
        let budgeted = RemoteScrollback.withinContentBudget(
            content,
            maxBytes: 1000
        )
        let remaining = budgeted.text.split(separator: "\n")
        #expect(remaining.count < 200)
        // The newest line is always kept and the cursor tracks the drop.
        #expect(remaining.last == "plain-line-200")
        #expect(budgeted.cursorRow == remaining.count - 1)
    }

    @Test("leaves content under the budget untouched")
    func contentBudgetKeepsSmallContent() {
        let content = RemotePaneContent(
            text: "one\ntwo",
            cursorRow: 1,
            cursorColumn: 0,
            styledLines: [styled("one"), styled("two")]
        )
        #expect(
            RemoteScrollback.withinContentBudget(content) == content
        )
    }

    @Test("flags a screen-sized buffer as alternate screen")
    func altScreenHeuristic() {
        let screenSized = RemoteScrollback.content(
            screenText: (1...24).map { "line-\($0)" }
                .joined(separator: "\n"),
            viewportTextFromCursor: nil,
            gridRows: 24
        )
        #expect(screenSized.altScreen)

        let withScrollback = RemoteScrollback.content(
            screenText: (1...50).map { "line-\($0)" }
                .joined(separator: "\n"),
            viewportTextFromCursor: nil,
            gridRows: 24
        )
        #expect(!withScrollback.altScreen)

        let unknownGrid = RemoteScrollback.content(
            screenText: "one",
            viewportTextFromCursor: nil
        )
        #expect(!unknownGrid.altScreen)
    }

    @Test("passes the full screen text through when under the line cap")
    func passesFullTextThrough() {
        let content = RemoteScrollback.content(
            screenText: "one\ntwo\nthree",
            viewportTextFromCursor: nil
        )
        #expect(content.text == "one\ntwo\nthree")
        #expect(content.cursorRow == nil)
        #expect(content.cursorColumn == nil)
    }

    @Test("maps a multi-line cursor suffix to its logical line and column")
    func mapsMultiLineSuffixToLineAndColumn() {
        // Screen has scrollback above, then three written lines. The
        // suffix "BB\nCCCC" is the tail of "BBBB" (from column 2) plus the
        // full "CCCC" line below it, so the cursor sits on "BBBB", column 2.
        let content = RemoteScrollback.content(
            screenText: "s1\ns2\nAAAA\nBBBB\nCCCC",
            viewportTextFromCursor: "BB\nCCCC"
        )
        #expect(content.cursorRow == 3)
        #expect(content.cursorColumn == 2)
    }

    @Test("an empty suffix places the cursor at the end of the last line")
    func emptySuffixPlacesCursorAtEndOfLastLine() {
        let content = RemoteScrollback.content(
            screenText: "one\ntwo\nthree",
            viewportTextFromCursor: ""
        )
        #expect(content.cursorRow == 2)
        #expect(content.cursorColumn == "three".count)
    }

    @Test("a Claude-style status suffix maps to the right row above the prompt")
    func mapsClaudeStyleStatusSuffix() {
        // The cursor sits at the end of the prompt line with nothing more
        // written on it (empty tail), and two full lines — a rule and a
        // status line — follow below it. That is a 3-element suffix
        // ("", "────", "status"), so rowsFromBottom is 3.
        let lines = [
            "output",
            "❯ aaaa",
            "────",
            "status",
        ]
        let content = RemoteScrollback.content(
            screenText: lines.joined(separator: "\n"),
            viewportTextFromCursor: "\n────\nstatus"
        )
        #expect(content.cursorRow == 1)
        #expect(content.cursorColumn == "❯ aaaa".count)
    }

    @Test("wide characters need no width math for the column")
    func wideCharactersNeedNoWidthMath() {
        // "あいu" is 3 characters (2 wide + 1 narrow); the suffix "u" is the
        // last character, so the column is a plain character-count
        // subtraction with no cell-width table involved.
        let content = RemoteScrollback.content(
            screenText: "あいu",
            viewportTextFromCursor: "u"
        )
        #expect(content.cursorRow == 0)
        #expect(content.cursorColumn == 2)
    }

    @Test("a soft-wrapped logical line stays one line on both sides")
    func softWrappedLineStaysOneLineOnBothSides() {
        // Ghostty unwraps a soft-wrapped logical line into a single line on
        // both the screen-text read and the cursor-suffix read, so the
        // suffix's tail still maps into that one logical line even though
        // it visually spans several grid rows.
        let wrapped = String(repeating: "あ", count: 7)
        let content = RemoteScrollback.content(
            screenText: "short\n\(wrapped)",
            viewportTextFromCursor: "ああ"
        )
        #expect(content.cursorRow == 1)
        #expect(content.cursorColumn == wrapped.count - 2)
    }

    @Test("caps the text to the newest lines and shifts the cursor row")
    func capsToNewestLines() {
        let lines = (1...10).map { "line-\($0)" }
        let content = RemoteScrollback.content(
            screenText: lines.joined(separator: "\n"),
            viewportTextFromCursor: "line-10",
            maxLines: 4
        )
        #expect(
            content.text == "line-7\nline-8\nline-9\nline-10"
        )
        // Cursor was on the absolute last row (10th line, index 9); after
        // dropping six lines it lands on index 3.
        #expect(content.cursorRow == 3)
        #expect(content.cursorColumn == 0)
    }
}
