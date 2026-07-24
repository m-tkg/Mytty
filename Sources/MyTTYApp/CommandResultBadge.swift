import AppKit

/// Text for the auto-fading badge shown when shell integration reports a
/// command finished. Free of window/view state so it stays unit-testable;
/// `CommandResultBadgeLayout` below handles placement.
enum CommandResultBadge {
    static func text(exitCode: Int?, durationNanoseconds: UInt64) -> String {
        let duration = formattedDuration(durationNanoseconds)
        guard let exitCode else { return duration }
        let symbol = exitCode == 0 ? "✓" : "✗"
        return "\(symbol) \(exitCode) · \(duration)"
    }

    /// Only a *known* non-zero exit code counts as a failure — an unknown
    /// code (shell integration didn't report one) is not treated as one.
    static func isFailure(exitCode: Int?) -> Bool {
        guard let exitCode else { return false }
        return exitCode != 0
    }

    private static let nanosecondsPerSecond = 1_000_000_000.0
    private static let oneSecond: UInt64 = 1_000_000_000
    private static let tenSeconds: UInt64 = 10_000_000_000
    private static let sixtySeconds: UInt64 = 60_000_000_000
    private static let oneHour: UInt64 = 3_600_000_000_000

    private static func formattedDuration(_ nanoseconds: UInt64) -> String {
        switch nanoseconds {
        case ..<oneSecond:
            let milliseconds = (Double(nanoseconds) / 1_000_000).rounded()
            return "\(Int(milliseconds))ms"
        case ..<tenSeconds:
            let seconds = Double(nanoseconds) / nanosecondsPerSecond
            return "\(String(format: "%.1f", seconds))s"
        case ..<sixtySeconds:
            let seconds = (Double(nanoseconds) / nanosecondsPerSecond)
                .rounded()
            return "\(Int(seconds))s"
        case ..<oneHour:
            let totalSeconds = roundedSeconds(nanoseconds)
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return "\(minutes)m \(String(format: "%02d", seconds))s"
        default:
            let totalSeconds = roundedSeconds(nanoseconds)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            return "\(hours)h \(String(format: "%02d", minutes))m"
        }
    }

    private static func roundedSeconds(_ nanoseconds: UInt64) -> UInt64 {
        UInt64((Double(nanoseconds) / nanosecondsPerSecond).rounded())
    }
}

/// Sizing and placement for the command result badge, anchored on the
/// cursor's row. Mirrors `PressedKeyToastLayout`'s shape: the view is NOT
/// flipped, so y grows upward.
@MainActor
enum CommandResultBadgeLayout {
    static let edgeInset: CGFloat = 6
    static let gap: CGFloat = 8
    static let height: CGFloat = 22
    static let horizontalPadding: CGFloat = 10
    static let cornerRadius: CGFloat = 5

    static func font(scale: CGFloat = 1) -> NSFont {
        .monospacedDigitSystemFont(ofSize: 12 * scale, weight: .semibold)
    }

    static func badgeSize(
        for text: String,
        maximumWidth: CGFloat
    ) -> NSSize {
        let label = NSTextField(labelWithString: text)
        label.font = font()
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        let width = min(
            label.fittingSize.width + horizontalPadding * 2,
            maximumWidth
        )
        return NSSize(width: width, height: height)
    }

    static func frame(
        cursorRect: NSRect,
        badgeSize: NSSize,
        in bounds: NSRect
    ) -> NSRect {
        let width = min(badgeSize.width, max(0, bounds.width - 2 * edgeInset))
        let height = min(
            badgeSize.height,
            max(0, bounds.height - 2 * edgeInset)
        )
        let minimumX = bounds.minX + edgeInset
        let x = max(minimumX, bounds.maxX - edgeInset - width)

        // The cursor sits under a vertically centered badge — lift the
        // badge above the cursor row instead so it never covers what is
        // being typed at the new prompt.
        let centeredY = cursorRect.midY - height / 2
        let y = cursorRect.maxX + gap > x
            ? cursorRect.maxY + gap
            : centeredY

        let minimumY = bounds.minY + edgeInset
        let maximumY = max(minimumY, bounds.maxY - edgeInset - height)
        let clampedY = min(max(y, minimumY), maximumY)

        return NSRect(x: x, y: clampedY, width: width, height: height)
    }
}
