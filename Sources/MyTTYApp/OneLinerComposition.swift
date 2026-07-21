import AppKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Prompt construction and output cleanup for the on-device one-liner
/// composer. Kept separate from the model call so the text handling is
/// testable without Foundation Models.
enum OneLinerPrompt {
    /// The on-device model is small, so the instructions carry explicit
    /// decision rules (file contents vs file names was a repeated
    /// misclassification) and few-shot examples — measured against the
    /// plain zero-shot prompt, these turn wrong `find -name` answers for
    /// content searches into the expected recursive grep, and turn
    /// mangled answers for "matches X but not Y" tasks into a
    /// `grep | grep -v` pipe. The example count is at the model's
    /// capacity: adding a seventh example measurably corrupted answers
    /// that were previously correct, so extend this prompt only with an
    /// eval run over the existing cases.
    static func instructions(language: ResolvedAppLanguage) -> String {
        let languageLine =
            switch language {
            case .english:
                "If you reply with a sentence, write it in English."
            case .japanese:
                "If you reply with a sentence, write it in Japanese."
            }
        return """
        You write shell one-liners for macOS (zsh). Reply with exactly \
        one command line and nothing else — no explanation, no code \
        fences, no leading $.

        Decision rules — read the task carefully:
        - Searching file CONTENTS (the text inside files; 中身, 内容, \
        ファイル内, 含まれている文字列): use grep recursively. NEVER use \
        find -name for contents.
        - Searching file NAMES (ファイル名): use find -name.
        - Always single-quote search patterns. Search strings from the \
        task are literal text — copy them exactly, never invent \
        character classes.
        - Only when the task EXCLUDES something (〜は含まない, \
        〜を除く, "but not"), pipe into grep -v with the excluded \
        string, as in the examples below. Otherwise never add grep -v.

        Examples:
        Task: ファイル名に log を含むファイルを探す
        Reply: find . -type f -name '*log*'
        Task: ファイルの中に TODO と書かれているファイルを探す
        Reply: find . -type f -print0 | xargs -0 grep -l 'TODO'
        Task: 「エラー」という文字列を含むファイルを一覧
        Reply: find . -type f -print0 | xargs -0 grep -l 'エラー'
        Task: list files larger than 100MB
        Reply: find . -type f -size +100M
        Task: foo で始まるが foobar は含まない行を検索
        Reply: grep -r '^foo' . | grep -v 'foobar'
        Task: warn を含むが warning は含まない行を検索
        Reply: grep -r 'warn' . | grep -v 'warning'

        If the task cannot reasonably be done in a single command line, \
        reply instead with one short sentence saying that it cannot and \
        why. \(languageLine)
        """
    }

    static func prompt(request: String) -> String {
        """
        Task: \(request.trimmingCharacters(in: .whitespacesAndNewlines))
        Reply:
        """
    }

    /// Reduces a model response to one usable line. Model output is
    /// untrusted: strip code fences, wrapping backticks, shell-prompt
    /// prefixes, and control characters.
    static func sanitize(_ raw: String) -> String? {
        var lines = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.first?.hasPrefix("```") == true {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        guard var line = lines.first(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else { return nil }
        line.removeAll { $0.isASCII && ($0.asciiValue ?? 0) < 0x20 }
        line = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["$ ", "% "] where line.hasPrefix(prefix) {
            line = String(line.dropFirst(prefix.count))
        }
        while line.count >= 2, line.hasPrefix("`"), line.hasSuffix("`") {
            line = String(line.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespaces)
        }
        line = line.trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }
}

/// Asks the on-device Apple Intelligence model to turn a natural-language
/// task into a shell one-liner. macOS 26+ only; nothing leaves the
/// machine.
@available(macOS 26, *)
enum OneLinerComposer {
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

    static func compose(
        request: String,
        language: ResolvedAppLanguage
    ) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(
            instructions: OneLinerPrompt.instructions(language: language)
        )
        // Greedy sampling keeps this precision task deterministic, and the
        // token cap stops the occasional runaway generation on quoted
        // Japanese input.
        guard let response = try? await session.respond(
            to: OneLinerPrompt.prompt(request: request),
            options: GenerationOptions(
                sampling: .greedy,
                maximumResponseTokens: 200
            )
        ) else { return nil }
        return OneLinerPrompt.sanitize(response.content)
        #else
        return nil
        #endif
    }
}

/// Floating panel for composing one-liners: a natural-language request
/// field with a Generate button, and a read-only result field with a Copy
/// button. The result is never executed — the user copies it.
@MainActor
final class OneLinerPanelController: NSObject {
    private let panel: NSPanel
    private let requestField: NSTextField
    private let generateButton: NSButton
    private let resultField: NSTextField
    private let copyButton: NSButton
    private let localizer: MyTTYLocalizer
    private let compose: (String) async -> String?
    private var compositionTask: Task<Void, Never>?
    private var composedCommand: String?

    init(
        localizer: MyTTYLocalizer,
        compose: @escaping (String) async -> String?
    ) {
        self.localizer = localizer
        self.compose = compose

        let width = 560.0
        let contentRect = NSRect(x: 0, y: 0, width: width, height: 104)
        panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = localizer[.composeOneLiner]
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false

        requestField = NSTextField(string: "")
        requestField.placeholderString =
            localizer[.oneLinerRequestPlaceholder]
        generateButton = NSButton(
            title: localizer[.generate], target: nil, action: nil
        )
        generateButton.bezelStyle = .rounded
        generateButton.keyEquivalent = "\r"

        resultField = NSTextField(string: "")
        resultField.isEditable = false
        resultField.isSelectable = true
        resultField.font = .monospacedSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .regular
        )
        resultField.lineBreakMode = .byTruncatingTail
        copyButton = NSButton(
            title: localizer[.copy], target: nil, action: nil
        )
        copyButton.bezelStyle = .rounded
        copyButton.isEnabled = false

        super.init()
        generateButton.target = self
        generateButton.action = #selector(generate(_:))
        copyButton.target = self
        copyButton.action = #selector(copyResult(_:))

        generateButton.sizeToFit()
        copyButton.sizeToFit()
        let buttonWidth = max(
            generateButton.frame.width, copyButton.frame.width
        )
        let fieldWidth = width - buttonWidth - 12 * 3
        requestField.frame = NSRect(x: 12, y: 64, width: fieldWidth, height: 24)
        generateButton.frame = NSRect(
            x: width - buttonWidth - 12, y: 62, width: buttonWidth, height: 28
        )
        resultField.frame = NSRect(x: 12, y: 20, width: fieldWidth, height: 24)
        copyButton.frame = NSRect(
            x: width - buttonWidth - 12, y: 18, width: buttonWidth, height: 28
        )

        let content = NSView(frame: contentRect)
        content.addSubview(requestField)
        content.addSubview(generateButton)
        content.addSubview(resultField)
        content.addSubview(copyButton)
        panel.contentView = content
        panel.initialFirstResponder = requestField
    }

    func show() {
        if !panel.isVisible {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(requestField)
    }

    func close() {
        compositionTask?.cancel()
        panel.close()
    }

    @objc private func generate(_ sender: Any?) {
        let request = requestField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, compositionTask == nil else { return }
        generateButton.isEnabled = false
        copyButton.isEnabled = false
        composedCommand = nil
        resultField.textColor = .secondaryLabelColor
        resultField.stringValue = localizer[.oneLinerGenerating]
        let failureText = localizer[.oneLinerFailed]
        compositionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let command = await compose(request)
            defer { compositionTask = nil }
            guard !Task.isCancelled else { return }
            generateButton.isEnabled = true
            if let command {
                composedCommand = command
                resultField.textColor = .labelColor
                resultField.stringValue = command
                resultField.toolTip = command
                copyButton.isEnabled = true
            } else {
                resultField.stringValue = failureText
            }
        }
    }

    @objc private func copyResult(_ sender: Any?) {
        guard let composedCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(composedCommand, forType: .string)
    }
}
