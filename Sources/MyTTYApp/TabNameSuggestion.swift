import AppKit
import MyTTYCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Builds the closure that reads the user's recent prompts to the pane's
/// AI agent. Everything main-thread-bound (provider, session ID, working
/// directory, foreground process) is captured up front; the returned
/// closure only does file reads, so it can run inside the detached
/// suggestion task. Providers whose local data does not reliably record
/// prompt text (OpenCode, Cursor, Antigravity) return nil and the tab
/// name falls back to buffer-only material.
enum AgentTabNamePromptSource {
    static func loader(
        provider: AgentProvider,
        sessionID: String?,
        workingDirectory: URL?,
        processID: pid_t
    ) -> (@Sendable () -> [String])? {
        let limit = TabNameSuggestionPrompt.maxUserPrompts
        switch provider {
        case .claudeCode:
            return {
                guard let transcript = ClaudeCodeSessionInspector
                    .transcriptURL(
                        sessionID: sessionID,
                        workingDirectory: workingDirectory
                    )
                else { return [] }
                return ClaudeCodeSessionInspector.recentUserPrompts(
                    contentsOf: transcript,
                    limit: limit
                )
            }
        case .codex:
            return {
                CodexSessionInspector.recentUserPrompts(
                    processID: processID,
                    limit: limit
                )
            }
        default:
            return nil
        }
    }
}

/// Prompt construction and output cleanup for the on-device tab-name
/// suggestion. Kept separate from the model call so the text handling is
/// testable without Foundation Models.
enum TabNameSuggestionPrompt {
    /// The model's context window is small, and the most recent output is
    /// what describes the tab's current activity, so only the buffer's
    /// tail is sent.
    static let maxBufferCharacters = 3000
    static let maxNameCharacters = 30
    /// How many of the user's recent agent prompts are sent as material.
    static let maxUserPrompts = 5

    static func instructions(language: ResolvedAppLanguage) -> String {
        let languageLine =
            switch language {
            case .english: "Answer in English."
            case .japanese: "Answer in Japanese."
            }
        return """
        You name terminal tabs. Given the recent output of a terminal — \
        and, when an AI agent runs in it, the user's recent requests to \
        that agent — answer with a short name (at most four words) \
        describing what the user is trying to accomplish, such as the \
        project, tool, or task. Answer with the name only — no quotes, no \
        punctuation around it, no explanation. \(languageLine)
        """
    }

    static func prompt(buffer: String) -> String {
        prompt(buffer: buffer, userPrompts: [])
    }

    /// When an AI agent runs in the pane, the user's recent prompts to it
    /// say what the user is trying to accomplish far better than the
    /// terminal output does, so they lead the prompt and the output only
    /// supplies surrounding context.
    static func prompt(buffer: String, userPrompts: [String]) -> String {
        let tail = String(buffer.suffix(maxBufferCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userPrompts.isEmpty else {
            return """
            Recent terminal output:

            \(tail)

            Name this tab.
            """
        }
        let requests = userPrompts.suffix(maxUserPrompts)
            .map { "- \($0)" }
            .joined(separator: "\n")
        return """
        The user's recent requests to the AI agent in this terminal, \
        oldest first:

        \(requests)

        Recent terminal output:

        \(tail)

        Name this tab after what the user is trying to accomplish.
        """
    }

    /// Reduces a model response to a usable single-line tab name, or nil
    /// when nothing usable remains. Model output is untrusted: strip
    /// control characters, wrapping quotes, and clamp the length.
    static func sanitize(_ raw: String) -> String? {
        let firstLine = raw
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard var name = firstLine else { return nil }
        name.removeAll { $0.isASCII && ($0.asciiValue ?? 0) < 0x20 }
        name = name.trimmingCharacters(in: .whitespaces)
        let quotePairs: [(Character, Character)] = [
            ("\"", "\""), ("'", "'"), ("`", "`"), ("“", "”"), ("「", "」"),
        ]
        while name.count >= 2,
              let first = name.first, let last = name.last,
              quotePairs.contains(where: { $0.0 == first && $0.1 == last }) {
            name = String(name.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespaces)
        }
        if name.count > maxNameCharacters {
            name = String(name.prefix(maxNameCharacters))
                .trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? nil : name
    }
}

/// Asks the on-device Apple Intelligence model for a tab name. macOS 26+
/// only; the buffer never leaves the machine.
@available(macOS 26, *)
enum TabNameSuggester {
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

    static func suggest(
        buffer: String,
        userPrompts: [String] = [],
        language: ResolvedAppLanguage
    ) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(
            instructions: TabNameSuggestionPrompt.instructions(
                language: language
            )
        )
        guard let response = try? await session.respond(
            to: TabNameSuggestionPrompt.prompt(
                buffer: buffer,
                userPrompts: userPrompts
            )
        ) else { return nil }
        return TabNameSuggestionPrompt.sanitize(response.content)
        #else
        return nil
        #endif
    }
}

/// How the rename alert obtains a suggestion: the buffer is captured
/// synchronously on the main thread at click time, and the model call runs
/// detached. Both matter because the alert runs modally — main-actor tasks
/// are not processed while `NSAlert.runModal` is on screen.
struct TabNameSuggestionRequest {
    let captureBuffer: () -> String?
    let suggest: @Sendable (String) async -> String?
}

/// Rename-tab alert accessory pairing the name field with an "Auto-Name"
/// button that fills the field with an on-device suggestion — it never
/// commits the rename, the user still decides with Save.
final class TabNameSuggestAccessoryView: NSView {
    let textField: NSTextField
    private let button: NSButton
    private let request: TabNameSuggestionRequest
    private var suggestionTask: Task<Void, Never>?

    init(
        textField: NSTextField,
        buttonTitle: String,
        request: TabNameSuggestionRequest
    ) {
        self.textField = textField
        self.request = request
        button = NSButton(
            title: buttonTitle, target: nil, action: nil
        )
        button.bezelStyle = .rounded
        button.controlSize = .small
        super.init(
            frame: NSRect(x: 0, y: 0, width: 320, height: 52)
        )
        button.target = self
        button.action = #selector(fillSuggestion(_:))
        button.sizeToFit()

        textField.frame = NSRect(x: 0, y: 28, width: 320, height: 24)
        textField.autoresizingMask = [.width]
        button.setFrameOrigin(NSPoint(x: 0, y: 0))
        addSubview(textField)
        addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        suggestionTask?.cancel()
    }

    @objc private func fillSuggestion(_ sender: Any?) {
        guard suggestionTask == nil,
              let buffer = request.captureBuffer()
        else { return }
        button.isEnabled = false
        let suggest = request.suggest
        suggestionTask = Task.detached { [weak self] in
            let name = await suggest(buffer)
            // Deliver on the run loop in modal-panel mode: the alert runs
            // modally, where main-actor task jobs are not processed.
            RunLoop.main.perform(
                inModes: [.modalPanel, .common, .default]
            ) { [weak self] in
                guard let self else { return }
                if let name {
                    textField.stringValue = name
                }
                button.isEnabled = true
                suggestionTask = nil
            }
        }
    }
}
