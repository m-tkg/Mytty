import Testing

@testable import MyTTYCore

@Suite("Shortcut hold recognizer")
struct ShortcutHoldRecognizerTests {
    enum Command: Equatable, Hashable, Sendable {
        case splitRight
        case splitDown
    }

    @Test("performs the tap action when the key is released early")
    func tapOnEarlyRelease() {
        var recognizer = ShortcutHoldRecognizer<Command>()

        let pressed = recognizer.keyDown(.splitRight, isRepeat: false)
        #expect(pressed == [.scheduleTimer(generation: 1)])
        #expect(recognizer.isTracking)

        let released = recognizer.keyUp()
        #expect(released == [.performTap(.splitRight)])
        #expect(!recognizer.isTracking)
    }

    @Test("performs the hold action when the timer fires while held")
    func holdOnTimerFire() {
        var recognizer = ShortcutHoldRecognizer<Command>()

        _ = recognizer.keyDown(.splitRight, isRepeat: false)
        let fired = recognizer.timerFired(generation: 1)
        #expect(fired == [.performHold(.splitRight)])

        // The eventual key release must not add a second split.
        #expect(recognizer.keyUp() == [])
        #expect(!recognizer.isTracking)
    }

    @Test("ignores auto-repeat key downs while holding and after firing")
    func swallowsAutoRepeat() {
        var recognizer = ShortcutHoldRecognizer<Command>()

        _ = recognizer.keyDown(.splitRight, isRepeat: false)
        #expect(recognizer.keyDown(.splitRight, isRepeat: true) == [])

        _ = recognizer.timerFired(generation: 1)
        #expect(recognizer.keyDown(.splitRight, isRepeat: true) == [])
    }

    @Test("ignores a stale timer after the key was already released")
    func ignoresStaleTimer() {
        var recognizer = ShortcutHoldRecognizer<Command>()

        _ = recognizer.keyDown(.splitRight, isRepeat: false)
        _ = recognizer.keyUp()

        // A second press schedules a new generation; the first press's
        // timer must not convert it into a hold.
        let pressed = recognizer.keyDown(.splitRight, isRepeat: false)
        #expect(pressed == [.scheduleTimer(generation: 2)])
        #expect(recognizer.timerFired(generation: 1) == [])

        let released = recognizer.keyUp()
        #expect(released == [.performTap(.splitRight)])
    }

    @Test("resolves a pending press as a tap when another hold command arrives")
    func tapFlushedByNextHoldCommand() {
        var recognizer = ShortcutHoldRecognizer<Command>()

        _ = recognizer.keyDown(.splitRight, isRepeat: false)
        let next = recognizer.keyDown(.splitDown, isRepeat: false)
        #expect(next == [
            .performTap(.splitRight),
            .scheduleTimer(generation: 2),
        ])

        #expect(recognizer.keyUp() == [.performTap(.splitDown)])
    }

    @Test("flush resolves a pending press as a tap")
    func flushResolvesPendingTap() {
        var recognizer = ShortcutHoldRecognizer<Command>()

        _ = recognizer.keyDown(.splitRight, isRepeat: false)
        #expect(recognizer.flush() == [.performTap(.splitRight)])
        #expect(!recognizer.isTracking)

        // Flushing when idle or after a hold already fired does nothing.
        #expect(recognizer.flush() == [])
        _ = recognizer.keyDown(.splitRight, isRepeat: false)
        _ = recognizer.timerFired(generation: 2)
        #expect(recognizer.flush() == [])
        #expect(recognizer.keyUp() == [])
    }

    @Test("ignores stray events while idle")
    func ignoresStrayEventsWhileIdle() {
        var recognizer = ShortcutHoldRecognizer<Command>()

        #expect(recognizer.keyUp() == [])
        #expect(recognizer.timerFired(generation: 1) == [])
        #expect(recognizer.keyDown(.splitRight, isRepeat: true) == [])
        #expect(!recognizer.isTracking)
    }
}
