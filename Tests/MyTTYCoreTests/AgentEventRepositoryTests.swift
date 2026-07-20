import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent event repository", .serialized)
struct AgentEventRepositoryTests {
    @Test("appends events once and preserves arrival order")
    func appendAndLoad() throws {
        let fixture = makeRepository()
        defer { fixture.remove() }
        let laterTimestamp = event(id: 1, occurredAt: 20)
        let earlierTimestamp = event(id: 2, occurredAt: 10)

        #expect(try fixture.repository.append(laterTimestamp))
        #expect(try fixture.repository.append(earlierTimestamp))
        #expect(try !fixture.repository.append(laterTimestamp))

        #expect(
            try fixture.repository.loadEvents()
                == [laterTimestamp, earlierTimestamp]
        )
    }

    @Test("records the first acknowledgement idempotently")
    func acknowledge() throws {
        let fixture = makeRepository()
        defer { fixture.remove() }
        let eventID = AgentEventID(rawValue: makeUUID(3))
        let first = Date(timeIntervalSince1970: 10)
        let retry = Date(timeIntervalSince1970: 20)

        #expect(
            try fixture.repository.acknowledge(
                eventID: eventID,
                at: first
            )
        )
        #expect(
            try !fixture.repository.acknowledge(
                eventID: eventID,
                at: retry
            )
        )

        #expect(
            try fixture.repository.loadAcknowledgements()
                == [
                    AttentionAcknowledgement(
                        eventID: eventID,
                        acknowledgedAt: first
                    ),
                ]
        )
    }

    @Test("coexists with the session snapshot in one database")
    func sharedDatabase() throws {
        let fixture = makeRepository()
        defer { fixture.remove() }
        let snapshotRepository = SQLiteSessionRepository(
            databaseURL: fixture.database
        )
        let snapshot = SessionSnapshot(windows: [])
        let agentEvent = event(id: 4, occurredAt: 30)

        try snapshotRepository.save(snapshot)
        _ = try fixture.repository.append(agentEvent)

        #expect(try snapshotRepository.load() == snapshot)
        #expect(try fixture.repository.loadEvents() == [agentEvent])
    }

    private func event(
        id: UInt8,
        occurredAt: TimeInterval
    ) -> AgentEvent {
        AgentEvent(
            id: AgentEventID(rawValue: makeUUID(id)),
            runID: AgentRunID(rawValue: makeUUID(10)),
            surfaceID: TerminalSurfaceID(rawValue: makeUUID(11)),
            provider: .openCode,
            kind: .running,
            occurredAt: Date(timeIntervalSince1970: occurredAt),
            message: "working"
        )
    }

    private func makeRepository() -> RepositoryFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let database = directory.appendingPathComponent("mytty.sqlite")
        return RepositoryFixture(
            directory: directory,
            database: database,
            repository: SQLiteAgentEventRepository(databaseURL: database)
        )
    }

    private func makeUUID(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
    }
}

private struct RepositoryFixture {
    let directory: URL
    let database: URL
    let repository: SQLiteAgentEventRepository

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
