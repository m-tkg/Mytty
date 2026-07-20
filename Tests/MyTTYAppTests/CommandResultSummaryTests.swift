import Foundation
import Testing

@testable import MyTTYApp

@Suite("Command result summary")
struct CommandResultSummaryTests {
    @Test("sends only the buffer tail to the model")
    func promptTruncatesBuffer() {
        let buffer = String(repeating: "x", count: 20_000) + "make test"
        let prompt = CommandResultSummaryPrompt.prompt(
            buffer: buffer,
            result: nil
        )
        #expect(prompt.contains("make test"))
        #expect(
            prompt.count
                < CommandResultSummaryPrompt.maxBufferCharacters + 300
        )
    }

    @Test("embeds the exit code state in the prompt")
    func promptEmbedsExitCode() {
        let success = CommandResultSummaryPrompt.prompt(
            buffer: "ok",
            result: LastCommandResult(exitCode: 0, finishedAt: .now)
        )
        #expect(success.contains("exited with code 0 (success)"))

        let failure = CommandResultSummaryPrompt.prompt(
            buffer: "boom",
            result: LastCommandResult(exitCode: 127, finishedAt: .now)
        )
        #expect(failure.contains("exited with code 127 (failure)"))

        let unknown = CommandResultSummaryPrompt.prompt(
            buffer: "hm",
            result: nil
        )
        #expect(unknown.contains("exit code is unknown"))
    }

    @Test("instructions pin the answer language and ask for detail")
    func instructionsLanguage() {
        let japanese = CommandResultSummaryPrompt.instructions(
            language: .japanese
        )
        #expect(japanese.contains("Answer in Japanese."))
        #expect(japanese.contains("DETAILED"))
        #expect(
            CommandResultSummaryPrompt.instructions(language: .english)
                .contains("Answer in English.")
        )
    }
}
