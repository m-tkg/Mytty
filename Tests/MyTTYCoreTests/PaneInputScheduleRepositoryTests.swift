import Foundation
import Testing

@testable import MyTTYCore

@Suite("Pane input schedule repository")
struct PaneInputScheduleRepositoryTests {
    @Test("round trips schedules and replaces an edited schedule")
    func roundTripAndUpdate() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let original = schedule(
            id: 1,
            surfaceID: 101,
            fireAt: 120,
            text: "echo original",
            appendNewline: true
        )
        let later = schedule(
            id: 2,
            surfaceID: 101,
            fireAt: 180,
            text: "echo later",
            appendNewline: false
        )

        try fixture.repository.upsert(later)
        try fixture.repository.upsert(original)

        #expect(try fixture.repository.load() == [original, later])
        #expect(original.input == "echo original\n")
        #expect(later.input == "echo later")

        let edited = schedule(
            id: 1,
            surfaceID: 101,
            fireAt: 240,
            text: "echo edited",
            appendNewline: false
        )
        try fixture.repository.upsert(edited)

        #expect(try fixture.repository.load() == [later, edited])
    }

    @Test("deletes expired, individual, and pane-scoped schedules")
    func deletion() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let expired = schedule(id: 1, surfaceID: 101, fireAt: 10)
        let firstPane = schedule(id: 2, surfaceID: 101, fireAt: 30)
        let secondPane = schedule(id: 3, surfaceID: 102, fireAt: 40)
        let individuallyDeleted = schedule(id: 4, surfaceID: 103, fireAt: 50)
        for item in [expired, firstPane, secondPane, individuallyDeleted] {
            try fixture.repository.upsert(item)
        }

        try fixture.repository.deleteExpired(atOrBefore: date(20))
        try fixture.repository.delete(id: individuallyDeleted.id)
        try fixture.repository.deleteAll(for: firstPane.surfaceID)

        #expect(try fixture.repository.load() == [secondPane])
    }

    private func schedule(
        id: UInt8,
        surfaceID: UInt8,
        fireAt: TimeInterval,
        text: String = "echo scheduled",
        appendNewline: Bool = true
    ) -> PaneInputSchedule {
        PaneInputSchedule(
            id: PaneInputScheduleID(rawValue: makeUUID(id)),
            surfaceID: TerminalSurfaceID(rawValue: makeUUID(surfaceID)),
            fireAt: date(fireAt),
            text: text,
            appendNewline: appendNewline
        )
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }

    private func makeUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
    }
}

private struct Fixture {
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
