import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite
struct RemoteCellWidthTests {
    @Test
    func asciiTakesOneCellPerCharacter() {
        #expect(RemoteCellWidth.displayWidth("hello") == 5)
        #expect(RemoteCellWidth.displayWidth("") == 0)
    }

    @Test
    func cjkTakesTwoCells() {
        #expect(RemoteCellWidth.displayWidth("日本語") == 6)
        #expect(RemoteCellWidth.displayWidth("あ") == 2)
        // Hangul syllables and fullwidth forms are wide too.
        #expect(RemoteCellWidth.displayWidth("한글") == 4)
        #expect(RemoteCellWidth.displayWidth("Ａ") == 2)
    }

    @Test
    func mixedTextSumsPerScalar() {
        #expect(RemoteCellWidth.displayWidth("a日b") == 4)
    }

    @Test
    func combiningMarksTakeNoCellOfTheirOwn() {
        // "e" plus a combining acute accent occupies one cell, not two —
        // getting this wrong shifts the rest of the line by a cell.
        #expect(RemoteCellWidth.displayWidth("e\u{0301}") == 1)
        #expect(RemoteCellWidth.displayWidth("\u{200B}") == 0)
    }

    @Test
    func emojiTakeTwoCells() {
        #expect(RemoteCellWidth.displayWidth("🚀") == 2)
        #expect(RemoteCellWidth.displayWidth("✅") == 2)
    }

    @Test
    func characterWidthUsesTheFirstNonZeroWidthScalar() {
        let accented: Character = "e\u{0301}"
        #expect(RemoteCellWidth.displayWidth(of: accented) == 1)

        let wide: Character = "日"
        #expect(RemoteCellWidth.displayWidth(of: wide) == 2)

        // A variation selector after a wide base must not add a cell.
        let emojiWithSelector: Character = "\u{2757}\u{FE0F}"
        #expect(RemoteCellWidth.displayWidth(of: emojiWithSelector) == 2)
    }

    @Test
    func boxDrawingStaysNarrow() {
        // TUI frames are drawn with these; treating them as wide would
        // shear every boxed panel a client mirrors.
        #expect(RemoteCellWidth.displayWidth("─│┌┐└┘") == 6)
    }
}
