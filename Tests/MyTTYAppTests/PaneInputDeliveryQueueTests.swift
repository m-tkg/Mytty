import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

/// Shared, order-preserving sink so assertions can read back what multiple
/// `FakeSurface`s (potentially across different panes) actually received,
/// and in what order — including after a surface has been "closed" and
/// deallocated.
@MainActor
private final class DeliveryLog {
    private(set) var entries: [String] = []
    func record(_ entry: String) { entries.append(entry) }
}

@MainActor
private final class FakeSurface: RemoteInputDeliverable {
    private let id: String
    private let log: DeliveryLog

    init(id: String, log: DeliveryLog) {
        self.id = id
        self.log = log
    }

    func sendText(_ text: String) { log.record("\(id):text:\(text)") }
    func sendEnter() { log.record("\(id):enter") }
}

@Suite("Pane input delivery queue")
struct PaneInputDeliveryQueueTests {
    @MainActor
    private func waitFor(
        _ log: DeliveryLog,
        count: Int
    ) async throws {
        for _ in 0..<100 where log.entries.count < count {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("a plain text send with nothing pending delivers synchronously")
    @MainActor
    func synchronousWhenIdle() {
        let log = DeliveryLog()
        let pane = TerminalSurfaceID()
        let panes: [TerminalSurfaceID: FakeSurface] = [
            pane: FakeSurface(id: "p", log: log)
        ]
        let queue = PaneInputDeliveryQueue<FakeSurface>(
            enterDelay: .seconds(60),
            target: { panes[$0] }
        )

        let accepted = queue.deliver(paneID: pane, text: "ls", pressEnter: false)

        #expect(accepted)
        // No async hop needed for a plain send: the text is already there.
        #expect(log.entries == ["p:text:ls"])
    }

    @Test("delivering to a pane that doesn't exist reports false and sends nothing")
    @MainActor
    func unknownPaneIsRejected() {
        let log = DeliveryLog()
        let panes: [TerminalSurfaceID: FakeSurface] = [:]
        let queue = PaneInputDeliveryQueue<FakeSurface>(
            enterDelay: .milliseconds(10),
            target: { panes[$0] }
        )

        let accepted = queue.deliver(
            paneID: TerminalSurfaceID(),
            text: "ls",
            pressEnter: true
        )

        #expect(!accepted)
        #expect(log.entries.isEmpty)
    }

    @Test("a burst of text+Enter calls for the same pane stays in order")
    @MainActor
    func backToBackCallsStayOrdered() async throws {
        // Reproduces the bug: `deliver("A", pressEnter: true)` immediately
        // followed by `deliver("B", pressEnter: true)` used to send "A"
        // and "B" back to back (both synchronous) and only then fire both
        // delayed Enters, landing "AB" at the PTY. The fix must interleave
        // them as A, Enter, B, Enter.
        let log = DeliveryLog()
        let pane = TerminalSurfaceID()
        let panes: [TerminalSurfaceID: FakeSurface] = [
            pane: FakeSurface(id: "p", log: log)
        ]
        let queue = PaneInputDeliveryQueue<FakeSurface>(
            enterDelay: .milliseconds(30),
            target: { panes[$0] }
        )

        #expect(queue.deliver(paneID: pane, text: "A", pressEnter: true))
        #expect(queue.deliver(paneID: pane, text: "B", pressEnter: true))

        // Immediately after both calls, only A's text has gone out — B is
        // queued behind A's still-pending Enter, not sent early.
        #expect(log.entries == ["p:text:A"])

        try await waitFor(log, count: 4)

        #expect(log.entries == ["p:text:A", "p:enter", "p:text:B", "p:enter"])
    }

    @Test("a third call queues behind the first two and still lands in order")
    @MainActor
    func threeCallsStayOrdered() async throws {
        let log = DeliveryLog()
        let pane = TerminalSurfaceID()
        let panes: [TerminalSurfaceID: FakeSurface] = [
            pane: FakeSurface(id: "p", log: log)
        ]
        let queue = PaneInputDeliveryQueue<FakeSurface>(
            enterDelay: .milliseconds(20),
            target: { panes[$0] }
        )

        #expect(queue.deliver(paneID: pane, text: "A", pressEnter: true))
        #expect(queue.deliver(paneID: pane, text: "B", pressEnter: true))
        #expect(queue.deliver(paneID: pane, text: "C", pressEnter: false))

        try await waitFor(log, count: 5)

        #expect(
            log.entries == [
                "p:text:A", "p:enter", "p:text:B", "p:enter", "p:text:C",
            ]
        )
    }

    @Test("independent panes don't block each other")
    @MainActor
    func independentPanesAreNotSerialized() async throws {
        let log = DeliveryLog()
        let pane1 = TerminalSurfaceID()
        let pane2 = TerminalSurfaceID()
        let panes: [TerminalSurfaceID: FakeSurface] = [
            pane1: FakeSurface(id: "p1", log: log),
            pane2: FakeSurface(id: "p2", log: log),
        ]
        let queue = PaneInputDeliveryQueue<FakeSurface>(
            enterDelay: .milliseconds(30),
            target: { panes[$0] }
        )

        #expect(queue.deliver(paneID: pane1, text: "A1", pressEnter: true))
        // pane2 has no pending Enter of its own, so this must go out
        // synchronously right away, not wait behind pane1's queue.
        #expect(queue.deliver(paneID: pane2, text: "B1", pressEnter: false))

        #expect(log.entries == ["p1:text:A1", "p2:text:B1"])

        try await waitFor(log, count: 3)

        #expect(log.entries == ["p1:text:A1", "p2:text:B1", "p1:enter"])
    }

    @Test("a pane closing while input is queued drops the queue without crashing")
    @MainActor
    func closedPaneDropsQueuedInput() async throws {
        let log = DeliveryLog()
        let pane = TerminalSurfaceID()
        var panes: [TerminalSurfaceID: FakeSurface] = [
            pane: FakeSurface(id: "p", log: log)
        ]
        let queue = PaneInputDeliveryQueue<FakeSurface>(
            enterDelay: .milliseconds(20),
            target: { panes[$0] }
        )

        #expect(queue.deliver(paneID: pane, text: "A", pressEnter: true))
        #expect(queue.deliver(paneID: pane, text: "B", pressEnter: true))
        #expect(log.entries == ["p:text:A"])

        // Drop every strong reference to the surface — mirrors a pane
        // closing while A's Enter is still in flight and B is queued
        // behind it. The queue's own capture of the surface is `weak`.
        panes.removeValue(forKey: pane)

        // Give the scheduled Enter time to fire (or not) and drain to run.
        try await Task.sleep(for: .milliseconds(100))

        // A's Enter is dropped (weak surface is gone by the time it
        // fires) and B is never sent — no crash, and nothing leaks out
        // after the pane closed.
        #expect(log.entries == ["p:text:A"])
    }
}
