import Foundation
import Testing

@testable import MyTTYCore

@Suite("Antigravity status line")
struct AntigravityStatusLineTests {
    private static let payload = Data("""
    {"session_id":"d3723fd1-d84a-4c0b-8e69-0cd7a6163f0d",
     "model":{"id":"Gemini 4 Argon (Medium)","display_name":"Gemini 4 Argon (Medium)"},
     "context_window":{"used_percentage":0.95,"remaining_percentage":99.05},
     "quota":{
       "3p-5h":{"remaining_fraction":1},
       "3p-weekly":{"remaining_fraction":0.9933576},
       "gemini-5h":{"remaining_fraction":0.5},
       "gemini-weekly":{"remaining_fraction":0.75}},
     "plan_tier":"Google AI Pro","email":"user@example.com"}
    """.utf8)

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    @Test("parses context, model and quota, and drops the email")
    func parse() throws {
        let snapshot = try #require(
            AntigravityStatusLineSnapshot.parse(Self.payload)
        )
        #expect(snapshot.sessionID == "d3723fd1-d84a-4c0b-8e69-0cd7a6163f0d")
        #expect(snapshot.modelName == "Gemini 4 Argon (Medium)")
        #expect(snapshot.contextRemainingPercent == 99.05)
        #expect(snapshot.planName == "Google AI Pro")
        #expect(snapshot.quota.count == 4)
        let summary = try #require(snapshot.usageSummary)
        #expect(summary.limits.map(\.title) == ["Gemini", "Claude/GPT"])
        #expect(summary.limits[0].remainingPercent == 50)
        #expect(abs(summary.limits[1].remainingPercent - 99.33576) < 0.0001)
    }

    @Test("derives remaining from used, clamps, and rejects bad identifiers")
    func validation() {
        let used = Data(#"{"session_id":"abc","context_window":{"used_percentage":130}}"#.utf8)
        #expect(
            AntigravityStatusLineSnapshot.parse(used)?
                .contextRemainingPercent == 0
        )
        for id in ["../etc", "a/b", "", "a b"] {
            let bad = Data(#"{"session_id":"\#(id)"}"#.utf8)
            #expect(AntigravityStatusLineSnapshot.parse(bad) == nil)
        }
        #expect(AntigravityStatusLineSnapshot.parse(Data("nope".utf8)) == nil)
        let noQuota = Data(#"{"session_id":"abc"}"#.utf8)
        #expect(AntigravityStatusLineSnapshot.parse(noQuota)?.usageSummary == nil)
    }

    @Test("store records per session and returns the newest fresh snapshot")
    func store() throws {
        let root = try temporaryDirectory()
        let store = AntigravityStatusLineStore(socketDirectory: root)

        #expect(try store.record(payload: Self.payload))
        #expect(try !store.record(payload: Data("{}".utf8)))
        let loaded = try #require(store.snapshot(
            sessionID: "d3723fd1-d84a-4c0b-8e69-0cd7a6163f0d"
        ))
        #expect(loaded.contextRemainingPercent == 99.05)
        #expect(store.snapshot(sessionID: "../x") == nil)
        #expect(store.latest(maxAge: 60) == loaded)
        #expect(store.latest(
            maxAge: 60,
            now: Date().addingTimeInterval(3600)
        ) == nil)
        let written = try FileManager.default.attributesOfItem(
            atPath: store.directory
                .appendingPathComponent(
                    "d3723fd1-d84a-4c0b-8e69-0cd7a6163f0d.json"
                ).path
        )
        #expect(written[.posixPermissions] as? Int == 0o600)
    }

    @Test("the inspector reports the per-session model and context from the snapshot")
    func inspector() throws {
        let root = try temporaryDirectory()
        let store = AntigravityStatusLineStore(socketDirectory: root)
        try store.record(payload: Self.payload)

        let status = AntigravitySessionInspector.status(
            sessionID: "d3723fd1-d84a-4c0b-8e69-0cd7a6163f0d",
            antigravityHome: root,
            statusLine: store
        )
        #expect(status?.contextRemainingPercent == 99.05)
        #expect(status?.modelName == "Gemini 4 Argon (Medium)")
        #expect(
            AntigravitySessionInspector.status(
                sessionID: "other",
                antigravityHome: root,
                statusLine: store
            ) == nil
        )
    }

    @Test("command round-trips, including quotes in the wrapped command")
    func command() {
        let hook = URL(fileURLWithPath: "/tmp/it's here/mytty-agent-hook")
        for original in [nil, "echo hi", "echo 'a' \"b\" $X", ""] {
            let command = AntigravityStatusLineCommand.command(
                hookExecutable: hook,
                wrapping: original
            )
            let expected = (original?.isEmpty ?? true) ? nil : original
            #expect(
                AntigravityStatusLineCommand.parse(command, hookExecutable: hook)
                    == .owned(wrapped: expected)
            )
        }
        #expect(
            AntigravityStatusLineCommand.parse("echo hi", hookExecutable: hook)
                == .notOwned
        )
    }
}
