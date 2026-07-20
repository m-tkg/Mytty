import AppKit

@MainActor
enum PressedKeyToastLayout {
    static let gap: CGFloat = 6
    static let edgeInset: CGFloat = 6
    static let height: CGFloat = 42
    static let minimumWidth: CGFloat = 54
    static let horizontalPadding: CGFloat = 14
    static let cornerRadius: CGFloat = 7

    static func font(scale: CGFloat = 1) -> NSFont {
        .monospacedSystemFont(ofSize: 17 * scale, weight: .semibold)
    }

    static func toastSize(
        for text: String,
        maximumWidth: CGFloat
    ) -> NSSize {
        let label = NSTextField(labelWithString: text)
        label.font = font()
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        return NSSize(
            width: min(
                max(
                    label.fittingSize.width + horizontalPadding * 2,
                    minimumWidth
                ),
                maximumWidth
            ),
            height: height
        )
    }

    static func frame(
        cursorRect: NSRect,
        toastSize: NSSize,
        in bounds: NSRect
    ) -> NSRect {
        let width = min(toastSize.width, max(0, bounds.width - 2 * edgeInset))
        let height = min(toastSize.height, max(0, bounds.height - 2 * edgeInset))
        let minimumX = bounds.minX + edgeInset
        let maximumX = max(minimumX, bounds.maxX - edgeInset - width)
        let centeredX = cursorRect.midX - width / 2
        let x = min(max(centeredX, minimumX), maximumX)

        let minimumY = bounds.minY + edgeInset
        let belowY = cursorRect.minY - gap - height
        let aboveY = cursorRect.maxY + gap
        let maximumY = max(minimumY, bounds.maxY - edgeInset - height)
        let y = belowY >= minimumY
            ? min(belowY, maximumY)
            : min(max(aboveY, minimumY), maximumY)

        return NSRect(x: x, y: y, width: width, height: height)
    }
}
