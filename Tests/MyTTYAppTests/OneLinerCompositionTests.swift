import Foundation
import Testing

@testable import MyTTYApp

@Suite("One-liner composition")
struct OneLinerCompositionTests {
    @Test("instructions pin the sentence language")
    func instructionsLanguage() {
        #expect(
            OneLinerPrompt.instructions(language: .english)
                .contains("write it in English.")
        )
        #expect(
            OneLinerPrompt.instructions(language: .japanese)
                .contains("write it in Japanese.")
        )
    }

    @Test("prompt trims the request")
    func promptTrimsRequest() {
        let prompt = OneLinerPrompt.prompt(request: "  find big files \n")
        #expect(prompt.contains("Task: find big files\n"))
    }

    @Test("instructions distinguish contents from names with examples")
    func instructionsCarryDecisionRules() {
        let instructions = OneLinerPrompt.instructions(language: .japanese)
        #expect(instructions.contains("NEVER use find -name for contents"))
        #expect(
            instructions.contains(
                "find . -type f -print0 | xargs -0 grep -l 'TODO'"
            )
        )
    }

    @Test("sanitize keeps a plain command unchanged")
    func sanitizePlain() {
        #expect(
            OneLinerPrompt.sanitize(
                #"find . -type f -exec grep -l "Test" {} +"#
            ) == #"find . -type f -exec grep -l "Test" {} +"#
        )
    }

    @Test("sanitize strips code fences")
    func sanitizeFences() {
        #expect(
            OneLinerPrompt.sanitize("```bash\nls -la\n```") == "ls -la"
        )
        #expect(OneLinerPrompt.sanitize("```\npwd\n```") == "pwd")
    }

    @Test("sanitize strips prompt prefixes and backticks")
    func sanitizePrefixes() {
        #expect(OneLinerPrompt.sanitize("$ ls") == "ls")
        #expect(OneLinerPrompt.sanitize("% ls") == "ls")
        #expect(OneLinerPrompt.sanitize("`ls -la`") == "ls -la")
    }

    @Test("sanitize keeps a cannot-do sentence intact")
    func sanitizeSentence() {
        let sentence = "これは1つのコマンドでは実現できません。対話的な操作が必要です。"
        #expect(OneLinerPrompt.sanitize(sentence) == sentence)
    }

    @Test("sanitize takes the first non-empty line and drops control characters")
    func sanitizeFirstLine() {
        #expect(
            OneLinerPrompt.sanitize("\n\nls\u{07} -la\nsecond") == "ls -la"
        )
    }

    @Test("sanitize rejects empty output")
    func sanitizeRejectsEmpty() {
        #expect(OneLinerPrompt.sanitize("") == nil)
        #expect(OneLinerPrompt.sanitize("```\n```") == nil)
    }
}
