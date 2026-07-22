import Foundation
import MyTTYCore
import MyTTYRemoteKit
import Testing

@testable import MyTTYApp

@Suite("Remote pane schedule service", .serialized)
struct RemotePaneScheduleServiceTests {
    @Test("lists a pane's schedules mapped to the wire type")
    @MainActor
    func listMapsFields() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let surface = surfaceID(1)
        let scheduleID = PaneInputScheduleID(rawValue: makeUUID(1))
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { _ in },
            onError: { _ in }
        )
        try scheduler.save(
            PaneInputSchedule(
                id: scheduleID,
                surfaceID: surface,
                fireAt: date(100),
                text: "echo hi",
                appendNewline: false
            ),
            now: date(10)
        )
        let service = makeService(scheduler: scheduler)

        let schedules = service.schedules(forPaneID: surface.rawValue.uuidString)

        #expect(schedules == [
            RemotePaneSchedule(
                id: scheduleID.rawValue.uuidString,
                fireAt: date(100),
                text: "echo hi",
                pressEnter: false
            ),
        ])
    }

    @Test("create is rejected for a pane that doesn't exist")
    @MainActor
    func createRejectedForUnknownPane() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let surface = surfaceID(1)
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { _ in },
            onError: { _ in }
        )
        let service = makeService(scheduler: scheduler, paneExists: { _ in false })

        service.create(
            RemotePaneSchedule(
                id: UUID().uuidString,
                fireAt: date(100),
                text: "echo hi",
                pressEnter: true
            ),
            forPaneID: surface.rawValue.uuidString
        )

        #expect(scheduler.schedules.isEmpty)
    }

    @Test("create and delete are rejected for malformed pane/schedule IDs")
    @MainActor
    func rejectsMalformedIdentifiers() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { _ in },
            onError: { _ in }
        )
        let service = makeService(scheduler: scheduler)

        service.create(
            RemotePaneSchedule(
                id: "not-a-uuid",
                fireAt: date(100),
                text: "echo hi",
                pressEnter: true
            ),
            forPaneID: surfaceID(1).rawValue.uuidString
        )
        service.create(
            RemotePaneSchedule(
                id: UUID().uuidString,
                fireAt: date(100),
                text: "echo hi",
                pressEnter: true
            ),
            forPaneID: "not-a-pane-id"
        )
        #expect(scheduler.schedules.isEmpty)
        #expect(service.schedules(forPaneID: "not-a-pane-id").isEmpty)

        service.delete(
            scheduleID: "not-a-uuid",
            forPaneID: surfaceID(1).rawValue.uuidString
        )
        service.delete(
            scheduleID: UUID().uuidString,
            forPaneID: "not-a-pane-id"
        )
        #expect(scheduler.schedules.isEmpty)
    }

    @Test("a past fireAt is dropped silently, without reporting an error")
    @MainActor
    func pastDateDroppedSilently() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let surface = surfaceID(1)
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { _ in },
            onError: { _ in }
        )
        var reportedErrors: [Error] = []
        let service = makeService(
            scheduler: scheduler,
            onError: { reportedErrors.append($0) }
        )

        service.create(
            RemotePaneSchedule(
                id: UUID().uuidString,
                fireAt: Date(timeIntervalSince1970: 1),
                text: "echo hi",
                pressEnter: true
            ),
            forPaneID: surface.rawValue.uuidString
        )

        #expect(scheduler.schedules.isEmpty)
        #expect(reportedErrors.isEmpty)
    }

    @Test("a schedule ID already owned by a different pane is rejected, leaving the original untouched")
    @MainActor
    func rejectsCrossPaneIDHijack() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let ownerSurface = surfaceID(1)
        let attackerSurface = surfaceID(2)
        let scheduleID = PaneInputScheduleID(rawValue: makeUUID(9))
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { _ in },
            onError: { _ in }
        )
        let original = PaneInputSchedule(
            id: scheduleID,
            surfaceID: ownerSurface,
            fireAt: date(1_000),
            text: "original text",
            appendNewline: true
        )
        try scheduler.save(original, now: date(10))
        let service = makeService(scheduler: scheduler)

        // The attacker learned `scheduleID` (e.g. by listing pane A's own
        // schedules) and tries to claim it for pane B.
        service.create(
            RemotePaneSchedule(
                id: scheduleID.rawValue.uuidString,
                fireAt: date(2_000),
                text: "hijacked text",
                pressEnter: false
            ),
            forPaneID: attackerSurface.rawValue.uuidString
        )

        #expect(scheduler.schedules == [original])
        #expect(
            service.schedules(forPaneID: attackerSurface.rawValue.uuidString)
                .isEmpty
        )
        #expect(
            service.schedules(forPaneID: ownerSurface.rawValue.uuidString)
                == [
                    RemotePaneSchedule(
                        id: scheduleID.rawValue.uuidString,
                        fireAt: date(1_000),
                        text: "original text",
                        pressEnter: true
                    ),
                ]
        )
    }

    @Test("reusing an ID already on the same pane updates it in place")
    @MainActor
    func sameSurfaceIDReuseUpdates() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let surface = surfaceID(1)
        let scheduleID = PaneInputScheduleID(rawValue: makeUUID(9))
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { _ in },
            onError: { _ in }
        )
        try scheduler.save(
            PaneInputSchedule(
                id: scheduleID,
                surfaceID: surface,
                fireAt: date(1_000),
                text: "original text",
                appendNewline: true
            ),
            now: date(10)
        )
        let service = makeService(scheduler: scheduler)

        // `service.create` calls the scheduler's real-clock `save`
        // (unlike the setup above, which pins `now` explicitly), so this
        // needs an actually-future date to avoid tripping `pastDate`.
        let futureFireAt = Date().addingTimeInterval(120)
        service.create(
            RemotePaneSchedule(
                id: scheduleID.rawValue.uuidString,
                fireAt: futureFireAt,
                text: "edited text",
                pressEnter: false
            ),
            forPaneID: surface.rawValue.uuidString
        )

        #expect(
            service.schedules(forPaneID: surface.rawValue.uuidString) == [
                RemotePaneSchedule(
                    id: scheduleID.rawValue.uuidString,
                    fireAt: futureFireAt,
                    text: "edited text",
                    pressEnter: false
                ),
            ]
        )
    }

    @Test("create rejects text over the maximum size")
    @MainActor
    func rejectsOversizedText() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let surface = surfaceID(1)
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { _ in },
            onError: { _ in }
        )
        let service = makeService(scheduler: scheduler)
        let oversizedText = String(
            repeating: "a",
            count: RemotePaneScheduleService.maximumTextBytes + 1
        )

        service.create(
            RemotePaneSchedule(
                id: UUID().uuidString,
                fireAt: date(1_000),
                text: oversizedText,
                pressEnter: true
            ),
            forPaneID: surface.rawValue.uuidString
        )

        #expect(scheduler.schedules.isEmpty)
    }

    @Test("delete only removes a schedule that belongs to the requesting pane")
    @MainActor
    func deleteOnlyRemovesOwnSchedule() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let ownerSurface = surfaceID(1)
        let otherSurface = surfaceID(2)
        let scheduleID = PaneInputScheduleID(rawValue: makeUUID(9))
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { _ in },
            onError: { _ in }
        )
        try scheduler.save(
            PaneInputSchedule(
                id: scheduleID,
                surfaceID: ownerSurface,
                fireAt: date(1_000),
                text: "echo hi",
                appendNewline: true
            ),
            now: date(10)
        )
        let service = makeService(scheduler: scheduler)

        // A different pane can't delete this schedule.
        service.delete(
            scheduleID: scheduleID.rawValue.uuidString,
            forPaneID: otherSurface.rawValue.uuidString
        )
        #expect(scheduler.schedules.count == 1)

        // The owning pane can.
        service.delete(
            scheduleID: scheduleID.rawValue.uuidString,
            forPaneID: ownerSurface.rawValue.uuidString
        )
        #expect(scheduler.schedules.isEmpty)
    }

    @Test("a non-pastDate persistence error is reported via onError")
    @MainActor
    func nonPastDateErrorReachesOnError() throws {
        let fixture = try SchedulerFixture()
        defer { fixture.cleanup() }
        let surface = surfaceID(1)
        let scheduler = PaneInputScheduler(
            repository: fixture.repository,
            timerEnabled: false,
            onFire: { _ in },
            onError: { _ in }
        )
        var reportedErrors: [Error] = []
        let service = makeService(
            scheduler: scheduler,
            onError: { reportedErrors.append($0) }
        )

        // Break the on-disk backing store: the repository re-creates its
        // parent directory on every call, which fails deterministically
        // once a plain file sits where that directory used to be.
        try FileManager.default.removeItem(at: fixture.root)
        try Data().write(to: fixture.root)

        // Future relative to the real clock: `save` uses the real clock
        // here (unlike the explicit `now:` used elsewhere in this file),
        // so a past date would be rejected as `pastDate` before ever
        // reaching the broken repository.
        service.create(
            RemotePaneSchedule(
                id: UUID().uuidString,
                fireAt: Date().addingTimeInterval(3_600),
                text: "echo hi",
                pressEnter: true
            ),
            forPaneID: surface.rawValue.uuidString
        )

        #expect(reportedErrors.count == 1)
    }

    @MainActor
    private func makeService(
        scheduler: PaneInputScheduler?,
        paneExists: @escaping (TerminalSurfaceID) -> Bool = { _ in true },
        onError: @escaping (Error) -> Void = { _ in }
    ) -> RemotePaneScheduleService {
        RemotePaneScheduleService(
            scheduler: scheduler,
            paneExists: paneExists,
            onError: onError
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
