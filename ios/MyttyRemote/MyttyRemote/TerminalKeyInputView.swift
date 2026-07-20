import SwiftUI
import UIKit

/// Invisible first-responder text view that drives terminal input. Unlike a
/// bare `UIKeyInput`, a `UITextView` supports *marked text*, so multi-stage
/// input methods — most importantly Japanese kanji conversion — compose on
/// the phone and only the committed result is sent. Direct input (Latin,
/// digits, symbols) commits immediately, one keystroke at a time, so the
/// terminal still feels responsive.
final class KeyCaptureTextView: UITextView, UITextViewDelegate {
    var onCommitText: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?
    /// The in-progress composition (marked text), or "" when nothing is
    /// being composed. Lets the UI preview what the IME is converting, since
    /// the invisible text view can't show the inline composition itself.
    var onCompositionChanged: ((String) -> Void)?

    init() {
        super.init(frame: .zero, textContainer: nil)
        delegate = self
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no
        // Keep the view invisible; input is driven programmatically.
        isScrollEnabled = false
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func textViewDidChange(_ textView: UITextView) {
        // While the IME is composing, don't send anything yet — just surface
        // the marked text so the UI can preview it.
        if let range = textView.markedTextRange {
            onCompositionChanged?(textView.text(in: range) ?? "")
            return
        }
        onCompositionChanged?("")
        guard !textView.text.isEmpty else { return }
        let committed = textView.text ?? ""
        // Clearing programmatically does not re-enter this delegate method.
        textView.text = ""
        onCommitText?(committed)
    }

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        // A deletion with nothing to delete locally is the terminal's
        // backspace; while composing, let the IME edit its marked text.
        if text.isEmpty,
           textView.markedTextRange == nil,
           textView.text.isEmpty {
            onDeleteBackward?()
            return false
        }
        return true
    }
}

struct TerminalKeyInput: UIViewRepresentable {
    @Binding var isFocused: Bool
    let onText: (String) -> Void
    let onBackspace: () -> Void
    var onComposition: (String) -> Void = { _ in }

    func makeUIView(context: Context) -> KeyCaptureTextView {
        let view = KeyCaptureTextView()
        view.onCommitText = onText
        view.onDeleteBackward = onBackspace
        view.onCompositionChanged = onComposition
        return view
    }

    func updateUIView(_ view: KeyCaptureTextView, context: Context) {
        view.onCommitText = onText
        view.onDeleteBackward = onBackspace
        view.onCompositionChanged = onComposition
        DispatchQueue.main.async {
            if isFocused, !view.isFirstResponder, view.window != nil {
                view.becomeFirstResponder()
            } else if !isFocused, view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
    }
}
