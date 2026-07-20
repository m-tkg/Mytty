import Foundation
import Testing

@testable import MyTTYCore

@Suite("Antigravity session inspection")
struct AntigravitySessionInspectorTests {
    @Test("reads the globally selected model from settings.json")
    func currentModel() {
        let data = Data("""
        {"model":"Gemini 3.5 Flash (Medium)","other":true}
        """.utf8)

        #expect(
            AntigravitySessionInspector.currentModelName(from: data)
                == "Gemini 3.5 Flash (Medium)"
        )
        #expect(
            AntigravitySessionInspector.currentModelName(from: Data("{}".utf8))
                == nil
        )
    }

    @Test("reads settings.json from disk and requires a hook session ID")
    func statusFromDisk() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        {"model":"Gemini 3.5 Flash (Medium)"}
        """.write(
            to: root.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )

        #expect(
            AntigravitySessionInspector.status(
                sessionID: "antigravity-session-id",
                antigravityHome: root
            ) == AgentSessionStatus(
                sessionID: "antigravity-session-id",
                modelName: "Gemini 3.5 Flash (Medium)",
                contextRemainingPercent: nil
            )
        )
        #expect(
            AntigravitySessionInspector.status(
                sessionID: nil,
                antigravityHome: root
            ) == nil
        )
    }

    @Test("returns nil when settings.json is missing")
    func missingSettings() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        #expect(
            AntigravitySessionInspector.status(
                sessionID: "antigravity-session-id",
                antigravityHome: missing
            ) == nil
        )
    }
}
