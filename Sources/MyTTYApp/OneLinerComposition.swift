import AppKit
import MyTTYCore
#if canImport(FoundationModels)
import FoundationModels
#endif

extension ResolvedAppLanguage {
    /// MyTTYCore's `OneLinerPrompt` only receives an already-resolved
    /// language, mirroring `paneTeamPointerLanguage`.
    var oneLinerLanguage: OneLinerLanguage {
        switch self {
        case .english: .english
        case .japanese: .japanese
        }
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
        // Default guardrails false-positive on harmless Japanese tasks
        // ("1MB より大きいファイルを探す" throws "sensitive or unsafe
        // content"); the reply is only ever copied by the user, never
        // executed, so the permissive transform guardrails are the
        // right trade-off.
        let session = LanguageModelSession(
            model: SystemLanguageModel(
                guardrails: .permissiveContentTransformations
            ),
            instructions: OneLinerPrompt.instructions(
                language: language.oneLinerLanguage
            )
        )
        // Greedy sampling keeps this precision task deterministic — the
        // deprecated `sampling:` label was silently ignored and sampled
        // randomly; `samplingMode:` is the one that works. The token cap
        // stops the occasional runaway generation on quoted Japanese
        // input.
        guard let response = try? await session.respond(
            to: OneLinerPrompt.prompt(request: request),
            options: GenerationOptions(
                samplingMode: .greedy,
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
