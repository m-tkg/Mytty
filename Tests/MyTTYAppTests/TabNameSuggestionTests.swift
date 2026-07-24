import Foundation
import Testing

@testable import MyTTYApp

@Suite("Tab name suggestion")
struct TabNameSuggestionTests {
    @Test("sends only the buffer tail to the model")
    func promptTruncatesBuffer() {
        let buffer = String(repeating: "x", count: 10_000) + "make test"
        let prompt = TabNameSuggestionPrompt.prompt(buffer: buffer)
        #expect(prompt.contains("make test"))
        #expect(
            prompt.count
                < TabNameSuggestionPrompt.maxBufferCharacters + 200
        )
    }

    @Test("prompt trims surrounding whitespace from the buffer")
    func promptTrimsWhitespace() {
        let prompt = TabNameSuggestionPrompt.prompt(
            buffer: "\n\n  swift build\n\n"
        )
        #expect(prompt.contains("swift build\n"))
        #expect(!prompt.contains("  swift build"))
    }

    @Test("user prompts to an AI agent lead the prompt when present")
    func promptIncludesUserPrompts() {
        let prompt = TabNameSuggestionPrompt.prompt(
            buffer: "some terminal output",
            userPrompts: ["fix the login bug", "add a regression test"]
        )
        #expect(prompt.contains("fix the login bug"))
        #expect(prompt.contains("add a regression test"))
        #expect(prompt.contains("some terminal output"))
        // The user's requests are the primary material, so they must come
        // before the terminal output.
        let promptIndex = prompt.range(of: "fix the login bug")!.lowerBound
        let bufferIndex = prompt.range(of: "some terminal output")!.lowerBound
        #expect(promptIndex < bufferIndex)
    }

    @Test("without user prompts the prompt matches the buffer-only form")
    func promptWithoutUserPrompts() {
        #expect(
            TabNameSuggestionPrompt.prompt(buffer: "ls", userPrompts: [])
                == TabNameSuggestionPrompt.prompt(buffer: "ls")
        )
    }

    @Test("only the most recent user prompts are included")
    func promptClampsUserPromptCount() {
        let prompts = (1...10).map { "request number \($0)" }
        let prompt = TabNameSuggestionPrompt.prompt(
            buffer: "output",
            userPrompts: prompts
        )
        #expect(!prompt.contains("request number 1\n"))
        #expect(prompt.contains("request number 10"))
        #expect(
            prompt.contains(
                "request number \(11 - TabNameSuggestionPrompt.maxUserPrompts)"
            )
        )
    }

    @Test("instructions pin the answer language")
    func instructionsLanguage() {
        #expect(
            TabNameSuggestionPrompt.instructions(language: .english)
                .contains("Answer in English.")
        )
        #expect(
            TabNameSuggestionPrompt.instructions(language: .japanese)
                .contains("Answer in Japanese.")
        )
    }

    @Test("sanitize keeps a plain name unchanged")
    func sanitizePlain() {
        #expect(
            TabNameSuggestionPrompt.sanitize("Build logs") == "Build logs"
        )
    }

    @Test("sanitize takes the first non-empty line")
    func sanitizeFirstLine() {
        #expect(
            TabNameSuggestionPrompt.sanitize(
                "\nRails server\nIt runs the app."
            ) == "Rails server"
        )
    }

    @Test("sanitize strips wrapping quotes")
    func sanitizeQuotes() {
        #expect(TabNameSuggestionPrompt.sanitize("\"deploy\"") == "deploy")
        #expect(TabNameSuggestionPrompt.sanitize("「デプロイ作業」") == "デプロイ作業")
        #expect(TabNameSuggestionPrompt.sanitize("“git rebase”") == "git rebase")
        #expect(TabNameSuggestionPrompt.sanitize("`npm test`") == "npm test")
    }

    @Test("sanitize removes control characters")
    func sanitizeControlCharacters() {
        #expect(
            TabNameSuggestionPrompt.sanitize("bui\u{07}ld\u{1B}[1m")
                == "build[1m"
        )
    }

    @Test("sanitize clamps overlong names")
    func sanitizeClampsLength() {
        let long = String(repeating: "a", count: 100)
        let sanitized = TabNameSuggestionPrompt.sanitize(long)
        #expect(
            sanitized?.count == TabNameSuggestionPrompt.maxNameCharacters
        )
    }

    @Test("sanitize rejects empty and whitespace-only output")
    func sanitizeRejectsEmpty() {
        #expect(TabNameSuggestionPrompt.sanitize("") == nil)
        #expect(TabNameSuggestionPrompt.sanitize("  \n\n  ") == nil)
        #expect(TabNameSuggestionPrompt.sanitize("\"\"") == nil)
    }
}
