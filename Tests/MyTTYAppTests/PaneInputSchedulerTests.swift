import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Pane input scheduler", .serialized)
struct PaneInputSchedulerTests {
    @Test("restores only future schedules for live panes")
    @MainActor
    func restoration() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let liveSurface = surfaceID(101)
        let staleSurface = surfaceID(102)
        let expired = schedule(1, surfaceID: liveSurface, fireAt: 10)
        let future = schedule(2, surfaceID: liveSurface, fireAt: 30)
        let orphaned = schedule(3, surfaceID: staleSurface, fireAt: 40)
        for item in [expired, future, orphaned] {
            try fixture.repository.upsert(item)
        }
        var delivered: [PaneInputSchedule] = []
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { delivered.append($0) },
            onError: { _ in }
        )

        try scheduler.reload(
            validSurfaceIDs: [liveSurface],
            now: date(20)
        )

        #expect(scheduler.schedules == [future])
        #expect(try fixture.repository.load() == [future])
        #expect(delivered.isEmpty)
    }

    @Test("fires due schedules once and removes them before delivery")
    @MainActor
    func firing() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let surface = surfaceID(101)
        let first = schedule(1, surfaceID: surface, fireAt: 30)
        let second = schedule(2, surfaceID: surface, fireAt: 40)
        var delivered: [PaneInputSchedule] = []
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { schedule in
                #expect((try? fixture.repository.load()) == [second])
                delivered.append(schedule)
            },
            onError: { _ in }
        )
        try scheduler.save(first, now: date(20))
        try scheduler.save(second, now: date(20))

        try scheduler.fireDue(now: date(35))
        try scheduler.fireDue(now: date(35))

        #expect(delivered == [first])
        #expect(scheduler.schedules == [second])
    }

    @Test("rejects past dates and deletes every schedule for a closed pane")
    @MainActor
    func validationAndPaneDeletion() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let firstSurface = surfaceID(101)
        let secondSurface = surfaceID(102)
        let first = schedule(1, surfaceID: firstSurface, fireAt: 30)
        let second = schedule(2, surfaceID: secondSurface, fireAt: 40)
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { _ in },
            onError: { _ in }
        )

        #expect(throws: PaneInputSchedulerError.pastDate) {
            try scheduler.save(first, now: date(30))
        }
        try scheduler.save(first, now: date(20))
        try scheduler.save(second, now: date(20))
        try scheduler.deleteAll(for: firstSurface, now: date(20))

        #expect(scheduler.schedules == [second])
        #expect(try fixture.repository.load() == [second])
    }

    private func schedule(
        _ id: UInt8,
        surfaceID: TerminalSurfaceID,
        fireAt: TimeInterval
    ) -> PaneInputSchedule {
        PaneInputSchedule(
            id: PaneInputScheduleID(rawValue: makeUUID(id)),
            surfaceID: surfaceID,
            fireAt: date(fireAt),
            text: "echo \(id)",
            appendNewline: true
        )
    }

    private func surfaceID(_ id: UInt8) -> TerminalSurfaceID {
        TerminalSurfaceID(rawValue: makeUUID(id))
    }

    private func makeUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}

private struct SchedulerFixture {
    let root: URL
    let repository: SQLitePaneInputScheduleRepository

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        repository = SQLitePaneInputScheduleRepository(
            databaseURL: root.appendingPathComponent("mytty.sqlite")
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
