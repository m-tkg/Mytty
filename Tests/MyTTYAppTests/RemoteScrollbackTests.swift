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
            viewportText: "one\ntwo\nthree",
            viewportCursor: nil,
            gridColumns: 80,
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
            viewportText: plain.suffix(3).joined(separator: "\n"),
            viewportCursor: (row: 2, column: 0),
            gridColumns: 80,
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
            viewportText: "",
            viewportCursor: nil,
            gridColumns: 80,
            gridRows: 24
        )
        #expect(screenSized.altScreen)

        let withScrollback = RemoteScrollback.content(
            screenText: (1...50).map { "line-\($0)" }
                .joined(separator: "\n"),
            viewportText: "",
            viewportCursor: nil,
            gridColumns: 80,
            gridRows: 24
        )
        #expect(!withScrollback.altScreen)

        let unknownGrid = RemoteScrollback.content(
            screenText: "one",
            viewportText: "",
            viewportCursor: nil,
            gridColumns: 80
        )
        #expect(!unknownGrid.altScreen)
    }

    @Test("passes the full screen text through when under the line cap")
    func passesFullTextThrough() {
        let content = RemoteScrollback.content(
            screenText: "one\ntwo\nthree",
            viewportText: "two\nthree",
            viewportCursor: nil,
            gridColumns: 80
        )
        #expect(content.text == "one\ntwo\nthree")
        #expect(content.cursorRow == nil)
        #expect(content.cursorColumn == nil)
    }

    @Test("remaps the viewport cursor into the full text from the bottom")
    func remapsViewportCursor() {
        // Screen buffer has 5 lines; the viewport shows the last 3, with
        // the cursor on the viewport's last row (row 2), column 4.
        let content = RemoteScrollback.content(
            screenText: "s1\ns2\nv1\nv2\nprompt",
            viewportText: "v1\nv2\nprompt",
            viewportCursor: (row: 2, column: 4),
            gridColumns: 80
        )
        #expect(content.cursorRow == 4)
        #expect(content.cursorColumn == 4)
    }

    @Test("keeps the cursor mapping when the buffer fits in one viewport")
    func mapsCursorWithoutScrollback() {
        let content = RemoteScrollback.content(
            screenText: "line\nprompt",
            viewportText: "line\nprompt",
            viewportCursor: (row: 1, column: 7),
            gridColumns: 80
        )
        #expect(content.cursorRow == 1)
        #expect(content.cursorColumn == 7)
    }

    @Test("a soft-wrapped viewport line does not shift the cursor down")
    func wrappedLineDoesNotShiftCursor() {
        // With 10 columns, the 25-cell line occupies 3 visual rows, so
        // the cursor's visual row 3 is still the second logical line.
        let wrapped = String(repeating: "x", count: 25)
        let content = RemoteScrollback.content(
            screenText: "old\n\(wrapped)\nprompt",
            viewportText: "\(wrapped)\nprompt",
            viewportCursor: (row: 3, column: 6),
            gridColumns: 10
        )
        #expect(content.cursorRow == 2)
        #expect(content.cursorColumn == 6)
    }

    @Test("a cursor on a wrapped line's later visual row maps into that line")
    func cursorInsideWrappedLine() {
        // Cursor on the wrapped line's second visual row, column 4:
        // cell offset 10 + 4 = character index 14 of the logical line.
        let wrapped = String(repeating: "x", count: 25)
        let content = RemoteScrollback.content(
            screenText: "\(wrapped)\nprompt",
            viewportText: "\(wrapped)\nprompt",
            viewportCursor: (row: 1, column: 4),
            gridColumns: 10
        )
        #expect(content.cursorRow == 0)
        #expect(content.cursorColumn == 14)
    }

    @Test("maps a cursor cell offset through double-width characters")
    func mapsCellOffsetThroughWideCharacters() {
        // "日本語" occupies 6 cells; the cursor cell just after it is
        // character index 3.
        let content = RemoteScrollback.content(
            screenText: "日本語abc",
            viewportText: "日本語abc",
            viewportCursor: (row: 0, column: 6),
            gridColumns: 80
        )
        #expect(content.cursorRow == 0)
        #expect(content.cursorColumn == 3)
    }

    @Test("a cursor below every written row lands past the last line")
    func cursorBelowWrittenRows() {
        let content = RemoteScrollback.content(
            screenText: "a\nb",
            viewportText: "a\nb",
            viewportCursor: (row: 4, column: 0),
            gridColumns: 80
        )
        #expect(content.cursorRow == 4)
        #expect(content.cursorColumn == 0)
    }

    @Test("a text-presentation emoji without VS16 counts as a single cell")
    func textPresentationEmojiIsNarrow() {
        // U+1F587 (🖇) has Emoji=Yes but Emoji_Presentation=No, so without
        // a following VS16 it renders (and should count) as narrow text,
        // matching ghostty's uucode-backed wcwidth.
        let line = "[app] \u{1F587} (main)$ aaa"
        #expect(RemoteScrollback.displayCells(of: line) == line.count)

        let cellOffset = line.count - 1 // cell just after the last "a"
        #expect(
            RemoteScrollback.characterIndex(
                forCellOffset: cellOffset,
                in: line
            ) == cellOffset
        )
    }

    @Test("VS16 forces an emoji-presentation cluster to double width")
    func variationSelector16WidensCluster() {
        let clipEmoji = "\u{1F587}\u{FE0F}" // 🖇️
        #expect(RemoteScrollback.displayCells(of: clipEmoji) == 2)
    }

    @Test("an emoji-default-presentation character is double width")
    func emojiPresentationDefaultIsWide() {
        #expect(RemoteScrollback.displayCells(of: "\u{231A}") == 2) // ⌚
    }

    @Test("VS15 forces an emoji-presentation cluster to single width")
    func variationSelector15NarrowsCluster() {
        let textScissors = "\u{2702}\u{FE0E}" // ✂ with VS15
        #expect(RemoteScrollback.displayCells(of: textScissors) == 1)
    }

    @Test("a CJK character stays double width")
    func cjkCharacterStaysWide() {
        #expect(RemoteScrollback.displayCells(of: "あ") == 2)
    }

    @Test("caps the text to the newest lines and shifts the cursor row")
    func capsToNewestLines() {
        let lines = (1...10).map { "line-\($0)" }
        let content = RemoteScrollback.content(
            screenText: lines.joined(separator: "\n"),
            viewportText: lines.suffix(3).joined(separator: "\n"),
            viewportCursor: (row: 2, column: 0),
            gridColumns: 80,
            maxLines: 4
        )
        #expect(
            content.text == "line-7\nline-8\nline-9\nline-10"
        )
        // Cursor was on the absolute last row (10th line, index 9); after
        // dropping six lines it lands on index 3.
        #expect(content.cursorRow == 3)
    }
}
