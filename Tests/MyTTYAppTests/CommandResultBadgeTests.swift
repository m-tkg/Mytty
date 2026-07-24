import AppKit
import Testing

@testable import MyTTYApp

@Suite("Command result badge")
struct CommandResultBadgeTests {
    @Test("formats sub-second durations as rounded milliseconds")
    func millisecondBucket() {
        #expect(
            CommandResultBadge.text(exitCode: nil, durationNanoseconds: 0)
                == "0ms"
        )
        #expect(
            CommandResultBadge.text(
                exitCode: nil,
                durationNanoseconds: 420_000_000
            ) == "420ms"
        )
        // Rounds rather than truncating.
        #expect(
            CommandResultBadge.text(
                exitCode: nil,
                durationNanoseconds: 420_600_000
            ) == "421ms"
        )
    }

    @Test("formats sub-ten-second durations with one decimal")
    func oneDecimalBucket() {
        #expect(
            CommandResultBadge.text(
                exitCode: nil,
                durationNanoseconds: 1_200_000_000
            ) == "1.2s"
        )
        #expect(
            CommandResultBadge.text(
                exitCode: nil,
                durationNanoseconds: 9_960_000_000
            ) == "10.0s"
        )
    }

    @Test("formats sub-minute durations as whole seconds")
    func wholeSecondBucket() {
        #expect(
            CommandResultBadge.text(
                exitCode: nil,
                durationNanoseconds: 12_000_000_000
            ) == "12s"
        )
        #expect(
            CommandResultBadge.text(
                exitCode: nil,
                durationNanoseconds: 59_600_000_000
            ) == "60s"
        )
    }

    @Test("formats sub-hour durations as minutes and zero-padded seconds")
    func minutesSecondsBucket() {
        #expect(
            CommandResultBadge.text(
                exitCode: nil,
                durationNanoseconds: 185_000_000_000
            ) == "3m 05s"
        )
        #expect(
            CommandResultBadge.text(
                exitCode: nil,
                durationNanoseconds: 60_000_000_000
            ) == "1m 00s"
        )
    }

    @Test("formats hour-plus durations as hours and zero-padded minutes")
    func hoursMinutesBucket() {
        #expect(
            CommandResultBadge.text(
                exitCode: nil,
                durationNanoseconds: 3_840_000_000_000
            ) == "1h 04m"
        )
        #expect(
            CommandResultBadge.text(
                exitCode: nil,
                durationNanoseconds: 3_600_000_000_000
            ) == "1h 00m"
        )
    }

    @Test("renders the three badge text shapes")
    func badgeTextShapes() {
        #expect(
            CommandResultBadge.text(
                exitCode: 0,
                durationNanoseconds: 1_200_000_000
            ) == "✓ 0 · 1.2s"
        )
        #expect(
            CommandResultBadge.text(
                exitCode: 130,
                durationNanoseconds: 1_200_000_000
            ) == "✗ 130 · 1.2s"
        )
        #expect(
            CommandResultBadge.text(
                exitCode: nil,
                durationNanoseconds: 1_200_000_000
            ) == "1.2s"
        )
    }

    @Test("only a known non-zero exit code counts as a failure")
    func isFailure() {
        #expect(!CommandResultBadge.isFailure(exitCode: nil))
        #expect(!CommandResultBadge.isFailure(exitCode: 0))
        #expect(CommandResultBadge.isFailure(exitCode: 1))
        #expect(CommandResultBadge.isFailure(exitCode: 130))
    }

    @Test("sizes the badge from its text and clamps to the maximum width")
    @MainActor
    func badgeSizing() {
        let size = CommandResultBadgeLayout.badgeSize(
            for: "✓ 0 · 1.2s",
            maximumWidth: 400
        )
        #expect(size.height == CommandResultBadgeLayout.height)
        #expect(size.width > 0)
        #expect(size.width <= 400)

        let clamped = CommandResultBadgeLayout.badgeSize(
            for: "✓ 0 · 1.2s",
            maximumWidth: 20
        )
        #expect(clamped.width == 20)
        #expect(clamped.height == CommandResultBadgeLayout.height)
    }

    @Test("right-aligns the badge to the pane's trailing edge")
    @MainActor
    func rightAligned() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        let badgeSize = NSSize(width: 100, height: 22)
        let cursorRect = NSRect(x: 50, y: 140, width: 8, height: 16)

        let frame = CommandResultBadgeLayout.frame(
            cursorRect: cursorRect,
            badgeSize: badgeSize,
            in: bounds
        )

        #expect(frame.width == 100)
        #expect(
            frame.maxX
                == bounds.maxX - CommandResultBadgeLayout.edgeInset
        )
    }

    @Test("vertically centers on the cursor's row when there's no overlap")
    @MainActor
    func verticallyCentered() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        let badgeSize = NSSize(width: 100, height: 22)
        let cursorRect = NSRect(x: 50, y: 140, width: 8, height: 16)

        let frame = CommandResultBadgeLayout.frame(
            cursorRect: cursorRect,
            badgeSize: badgeSize,
            in: bounds
        )

        #expect(frame.midY == cursorRect.midY)
    }

    @Test("lifts above the cursor row when the badge would cover it")
    @MainActor
    func liftsAboveCursor() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        let badgeSize = NSSize(width: 100, height: 22)
        // Near the pane's right edge, under where a right-aligned badge sits.
        let cursorRect = NSRect(x: 320, y: 140, width: 8, height: 16)

        let frame = CommandResultBadgeLayout.frame(
            cursorRect: cursorRect,
            badgeSize: badgeSize,
            in: bounds
        )

        #expect(frame.minY == cursorRect.maxY + CommandResultBadgeLayout.gap)
    }

    @Test("stays inside the pane's edges near the top and bottom")
    @MainActor
    func staysInsidePaneEdges() {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 300)
        let badgeSize = NSSize(width: 100, height: 22)

        let nearTop = CommandResultBadgeLayout.frame(
            cursorRect: NSRect(x: 50, y: 290, width: 8, height: 16),
            badgeSize: badgeSize,
            in: bounds
        )
        #expect(
            nearTop.maxY
                == bounds.maxY - CommandResultBadgeLayout.edgeInset
        )

        let nearBottom = CommandResultBadgeLayout.frame(
            cursorRect: NSRect(x: 50, y: 0, width: 8, height: 16),
            badgeSize: badgeSize,
            in: bounds
        )
        #expect(
            nearBottom.minY
                == bounds.minY + CommandResultBadgeLayout.edgeInset
        )
    }
}
