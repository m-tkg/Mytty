import Testing

@testable import MyTTYCore

@Suite("Terminal history")
struct TerminalHistoryTests {
    @Test("keeps ANSI history that fits the limit")
    func keepsHistory() {
        let history = "\u{1B}[31mred\u{1B}[0m\r\n"

        #expect(TerminalHistory.bounded(history) == history)
    }

    @Test("trims at a line boundary and resets inherited attributes")
    func trimsAtLineBoundary() {
        let history = "discarded\r\n\u{1B}[32mgreen\u{1B}[0m"

        let result = TerminalHistory.bounded(history, maximumUTF8Bytes: 20)

        #expect(result == "\u{1B}[0m\u{1B}[32mgreen\u{1B}[0m")
    }

    @Test("omits an oversized single line instead of restoring corrupt VT")
    func omitsOversizedSingleLine() {
        #expect(TerminalHistory.bounded("abcdefgh", maximumUTF8Bytes: 4) == nil)
    }

    @Test("drops the trailing blank viewport rows entirely")
    func dropsTrailingBlankRows() {
        let history = "prompt$ one\r\nprompt$ \u{1B}[0m"
            + String(repeating: "\r\n", count: 40)

        #expect(
            TerminalHistory.sanitized(history)
                == "prompt$ one\r\nprompt$ \u{1B}[0m"
        )
    }

    @Test("caps interior blank runs so restores stop compounding them")
    func capsInteriorBlankRuns() {
        let history = "old prompt$"
            + String(repeating: "\r\n", count: 300)
            + "new prompt$"

        let result = TerminalHistory.sanitized(history, maximumBlankRun: 8)

        #expect(
            result == "old prompt$"
                + String(repeating: "\r\n", count: 9)
                + "new prompt$"
        )
    }

    @Test("keeps short intentional gaps untouched")
    func keepsShortGaps() {
        let history = "a\r\n\r\n\r\nb"

        #expect(TerminalHistory.sanitized(history) == history)
    }
}
