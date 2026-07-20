import AppKit
import Testing

@testable import MyTTYApp

@Suite("Pressed key toast layout")
struct PressedKeyToastLayoutTests {
    @Test("sizes pressed key toasts without truncating key names")
    @MainActor
    func pressedKeyToastWidth() {
        for text in ["Delete", "Return", "⌥⇧Delete"] {
            let label = NSTextField(labelWithString: text)
            label.font = PressedKeyToastLayout.font()
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            let toastSize = PressedKeyToastLayout.toastSize(
                for: text,
                maximumWidth: 400
            )
            let availableTextWidth = toastSize.width
                - PressedKeyToastLayout.horizontalPadding * 2

            #expect(availableTextWidth >= label.fittingSize.width)
        }
    }
}
