import SwiftUI
import UIKit

/// Read-only, selectable snapshot of a pane's text. The inline pane view
/// can't offer real selection: its `Text` chunks are rebuilt on every
/// screen update, which destroys an in-progress selection, and SwiftUI
/// `Text` on iOS only selects whole blocks anyway. This sheet freezes the
/// buffer in a native `UITextView`, so the standard long-press range
/// selection and Copy menu just work.
struct PaneTextSelectionView: View {
    let text: String

    @Environment(\.dismiss) private var dismiss
    @State private var copiedAll = false

    var body: some View {
        NavigationStack {
            SelectableTextView(text: text)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            UIPasteboard.general.string = text
                            copiedAll = true
                        } label: {
                            Label(
                                copiedAll ? "Copied" : "Copy All",
                                systemImage: copiedAll
                                    ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .disabled(copiedAll)
                    }
                }
        }
    }
}

private struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> TailAnchoredTextView {
        // TextKit 1: its layout is complete when queried, so the tail
        // scroll lands on real content. TextKit 2's lazily estimated
        // layout can put the offset past what has been laid out, showing
        // an empty view until the user drags.
        let view = TailAnchoredTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .systemBackground
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textContainerInset = UIEdgeInsets(
            top: 8, left: 8, bottom: 8, right: 8
        )
        view.text = text
        return view
    }

    func updateUIView(_ view: TailAnchoredTextView, context: Context) {
        if view.text != text { view.text = text }
    }
}

/// Opens scrolled to the end, like the terminal view. The scroll must
/// wait for the first real layout: issuing it from `makeUIView` (even
/// deferred a runloop) runs while the sheet is still laying out and the
/// view has zero size, which pushed the content offset past the text and
/// left the sheet looking empty until the user dragged.
private final class TailAnchoredTextView: UITextView {
    private var didScrollToTail = false

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !didScrollToTail, bounds.height > 0 else { return }
        didScrollToTail = true
        let end = NSRange(location: (text as NSString).length, length: 0)
        DispatchQueue.main.async { [weak self] in
            self?.scrollRangeToVisible(end)
        }
    }
}
