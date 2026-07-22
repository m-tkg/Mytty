import Foundation

/// Distinguishes a quick tap of a shortcut from holding it down, so a
/// single binding can carry two actions (e.g. split vs. outer split).
///
/// The recognizer is a pure state machine: the caller feeds it key events
/// and timer callbacks, and executes the returned actions. Timers are
/// identified by a generation counter so a timer scheduled for an earlier
/// press can never resolve a later one.
public struct ShortcutHoldRecognizer<Command: Hashable & Sendable>: Sendable {
    public enum Action: Equatable, Sendable {
        /// Start a hold timer; report it back via `timerFired(generation:)`.
        case scheduleTimer(generation: Int)
        /// The press ended before the timer: run the shortcut's tap action.
        case performTap(Command)
        /// The key stayed down past the threshold: run the hold action.
        case performHold(Command)
    }

    private enum State: Equatable {
        case idle
        case holding(Command, generation: Int)
        case fired(Command)
    }

    private var state: State = .idle
    private var generation = 0

    public init() {}

    /// Whether a press is being tracked (holding or waiting for the
    /// release after a hold fired). The caller should route key-up events
    /// of the tracked key here while this is true.
    public var isTracking: Bool {
        state != .idle
    }

    /// A key-down of a hold-capable command. The caller consumes the
    /// event regardless of the returned actions.
    public mutating func keyDown(
        _ command: Command,
        isRepeat: Bool
    ) -> [Action] {
        switch state {
        case .idle:
            guard !isRepeat else { return [] }
            return [beginHold(command)]

        case let .holding(held, _):
            if isRepeat { return [] }
            // A different hold command before release: settle the pending
            // press as a tap, then start tracking the new one.
            return [.performTap(held), beginHold(command)]

        case .fired:
            if isRepeat { return [] }
            return [beginHold(command)]
        }
    }

    /// The tracked key was released.
    public mutating func keyUp() -> [Action] {
        switch state {
        case .idle:
            return []
        case let .holding(held, _):
            state = .idle
            return [.performTap(held)]
        case .fired:
            state = .idle
            return []
        }
    }

    /// Settles a pending press as a tap without a release, e.g. when an
    /// unrelated key event needs to be routed in order.
    public mutating func flush() -> [Action] {
        guard case let .holding(held, _) = state else { return [] }
        state = .idle
        return [.performTap(held)]
    }

    /// Abandons the tracked press without performing anything, e.g. when
    /// the app resigns active and the matching key-up will never arrive.
    /// Any scheduled timer becomes a no-op.
    public mutating func cancel() {
        state = .idle
    }

    /// The timer scheduled by `.scheduleTimer` elapsed. Stale generations
    /// are ignored.
    public mutating func timerFired(generation: Int) -> [Action] {
        guard case let .holding(held, current) = state,
              current == generation
        else { return [] }
        state = .fired(held)
        return [.performHold(held)]
    }

    private mutating func beginHold(_ command: Command) -> Action {
        generation += 1
        state = .holding(command, generation: generation)
        return .scheduleTimer(generation: generation)
    }
}
