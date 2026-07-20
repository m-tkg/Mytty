import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The most recent command completion reported by a surface's shell
/// integration, kept so the summary can tell the model whether the
/// command succeeded.
struct LastCommandResult: Equatable {
    var exitCode: Int?
    var finishedAt: Date
}

/// Prompt construction for the on-device last-command summary. Kept
/// separate from the model call so the text handling is testable without
/// Foundation Models.
enum CommandResultSummaryPrompt {
    /// Deliberately generous: this feature exists because a short summary
    /// drops detail, so most of the model's context goes to the output
    /// being summarized.
    static let maxBufferCharacters = 4000

    static func instructions(language: ResolvedAppLanguage) -> String {
        let languageLine =
            switch language {
            case .english: "Answer in English."
            case .japanese: "Answer in Japanese."
            }
        return """
        You explain the result of the most recent command in a terminal. \
        Identify the last command in the output, then produce a DETAILED \
        summary of its result: what the command was, what it did, and the \
        concrete details of its output — keep specific numbers, names, \
        paths, and versions rather than generalizing them away. If the \
        command failed or printed errors or warnings, explain each error: \
        what it means, its likely cause, and how it could be fixed. Use \
        short bullet points grouped under brief headings. Ignore output \
        from earlier commands except as context. \(languageLine)
        """
    }

    static func prompt(
        buffer: String,
        result: LastCommandResult?
    ) -> String {
        let tail = String(buffer.suffix(maxBufferCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let exitLine =
            switch result?.exitCode {
            case .none:
                "The last command's exit code is unknown."
            case .some(0):
                "The last command exited with code 0 (success)."
            case .some(let code):
                "The last command exited with code \(code) (failure)."
            }
        return """
        Recent terminal output:

        \(tail)

        \(exitLine)
        Summarize the last command's result in detail.
        """
    }
}

/// Asks the on-device Apple Intelligence model to summarize the last
/// command's result. macOS 26+ only; the buffer never leaves the machine.
@available(macOS 26, *)
enum CommandResultSummarizer {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
        #else
        return false
        #endif
    }

    static func summarize(
        buffer: String,
        result: LastCommandResult?,
        language: ResolvedAppLanguage
    ) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(
            instructions: CommandResultSummaryPrompt.instructions(
                language: language
            )
        )
        guard let response = try? await session.respond(
            to: CommandResultSummaryPrompt.prompt(
                buffer: buffer,
                result: result
            ),
            options: GenerationOptions(maximumResponseTokens: 800)
        ) else { return nil }
        let text = response.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
        #else
        return nil
        #endif
    }
}
