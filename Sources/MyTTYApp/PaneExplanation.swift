import AppKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Prompt construction for the on-device pane explanation. Kept separate
/// from the model call so the text handling is testable without
/// Foundation Models.
enum PaneExplanationPrompt {
    /// The model's context window is small; the buffer tail describes the
    /// pane's current activity best.
    static let maxBufferCharacters = 4000

    static func instructions(language: ResolvedAppLanguage) -> String {
        let languageLine =
            switch language {
            case .english: "Answer in English."
            case .japanese: "Answer in Japanese."
            }
        return """
        You explain terminal sessions. Given the recent output of one \
        terminal pane, explain concisely what the user has been doing in \
        it and what state it is in now: the commands run, what they did, \
        and any errors or results worth noting. Use a few short sentences \
        or bullet points — no preamble, no advice unless something \
        clearly failed. \(languageLine)
        """
    }

    static func prompt(buffer: String) -> String {
        let tail = String(buffer.suffix(maxBufferCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Recent output of the terminal pane:

        \(tail)

        Explain what is happening in this pane.
        """
    }
}

/// Asks the on-device Apple Intelligence model to explain the focused
/// pane. macOS 26+ only; the buffer never leaves the machine.
@available(macOS 26, *)
enum PaneExplainer {
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

    static func explain(
        buffer: String,
        language: ResolvedAppLanguage
    ) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let session = LanguageModelSession(
            instructions: PaneExplanationPrompt.instructions(
                language: language
            )
        )
        guard let response = try? await session.respond(
            to: PaneExplanationPrompt.prompt(buffer: buffer)
        ) else { return nil }
        let text = response.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
        #else
        return nil
        #endif
    }
}

/// Floating panel showing the explanation of the focused pane: a spinner
/// while the model runs, then the selectable result text.
final class PaneExplanationPanelController {
    private let panel: NSPanel
    private let textView: NSTextView
    private let spinner: NSProgressIndicator

    init(title: String) {
        let contentRect = NSRect(x: 0, y: 0, width: 440, height: 280)
        panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = title
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: contentRect)
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        let text = NSTextView(frame: contentRect)
        text.isEditable = false
        text.isSelectable = true
        text.font = .systemFont(ofSize: NSFont.systemFontSize)
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.autoresizingMask = [.width]
        scroll.documentView = text
        textView = text

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false
        spinner.sizeToFit()

        let content = NSView(frame: contentRect)
        content.autoresizesSubviews = true
        content.addSubview(scroll)
        content.addSubview(spinner)
        spinner.setFrameOrigin(
            NSPoint(
                x: (contentRect.width - spinner.frame.width) / 2,
                y: (contentRect.height - spinner.frame.height) / 2
            )
        )
        spinner.autoresizingMask = [
            .minXMargin, .maxXMargin, .minYMargin, .maxYMargin,
        ]
        panel.contentView = content
    }

    func beginAnalyzing(statusText: String, near window: NSWindow?) {
        textView.textColor = .secondaryLabelColor
        textView.string = statusText
        spinner.startAnimation(nil)
        if !panel.isVisible {
            if let frame = window?.frame {
                panel.setFrameOrigin(
                    NSPoint(
                        x: frame.midX - panel.frame.width / 2,
                        y: frame.midY - panel.frame.height / 2
                    )
                )
            } else {
                panel.center()
            }
        }
        panel.orderFront(nil)
    }

    func show(explanation: String) {
        spinner.stopAnimation(nil)
        textView.textColor = .labelColor
        textView.string = explanation
        textView.scroll(.zero)
    }

    func showFailure(_ message: String) {
        spinner.stopAnimation(nil)
        textView.textColor = .secondaryLabelColor
        textView.string = message
    }

    func close() {
        panel.close()
    }
}
