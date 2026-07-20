import Foundation
import Testing

@testable import MyTTYApp

@Suite("Pane explanation")
struct PaneExplanationTests {
    @Test("sends only the buffer tail to the model")
    func promptTruncatesBuffer() {
        let buffer = String(repeating: "x", count: 20_000) + "swift test"
        let prompt = PaneExplanationPrompt.prompt(buffer: buffer)
        #expect(prompt.contains("swift test"))
        #expect(
            prompt.count
                < PaneExplanationPrompt.maxBufferCharacters + 200
        )
    }

    @Test("prompt trims surrounding whitespace from the buffer")
    func promptTrimsWhitespace() {
        let prompt = PaneExplanationPrompt.prompt(
            buffer: "\n\n  git status\n\n"
        )
        #expect(prompt.contains("git status\n"))
        #expect(!prompt.contains("  git status"))
    }

    @Test("instructions pin the answer language")
    func instructionsLanguage() {
        #expect(
            PaneExplanationPrompt.instructions(language: .english)
                .contains("Answer in English.")
        )
        #expect(
            PaneExplanationPrompt.instructions(language: .japanese)
                .contains("Answer in Japanese.")
        )
    }
}
