import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent hook bridge")
struct AgentHookBridgeTests {
    @Test("ignores a global agent hook when it runs outside Mytty")
    func outsideMytty() throws {
        let delivery = try AgentHookBridge.makeDelivery(
            provider: .claudeCode,
            payload: Data(
                """
                {
                  "session_id": "claude-session",
                  "hook_event_name": "Stop"
                }
                """.utf8
            ),
            environment: [:],
            occurredAt: Date(timeIntervalSince1970: 1_721_113_200)
        )

        #expect(delivery == nil)
    }

    @Test("builds a capability-scoped delivery from the terminal environment")
    func delivery() throws {
        let payload = Data(
            """
            {
              "session_id": "codex-session",
              "turn_id": "codex-turn",
              "cwd": "/Users/tester/project",
              "hook_event_name": "PermissionRequest",
              "tool_name": "Bash"
            }
            """.utf8
        )
        let surfaceID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000201"
        )!

        let optionalDelivery = try AgentHookBridge.makeDelivery(
            provider: .codex,
            payload: payload,
            environment: [
                "MYTTY_EVENT_SOCKET": "/private/tmp/mytty.sock",
                "MYTTY_SURFACE_ID": surfaceID.uuidString,
                "MYTTY_EVENT_CAPABILITY": "surface-capability",
            ],
            occurredAt: Date(timeIntervalSince1970: 1_721_113_200)
        )
        let delivery = try #require(optionalDelivery)

        #expect(delivery.socketURL.path == "/private/tmp/mytty.sock")
        #expect(delivery.envelope.capability == "surface-capability")
        #expect(delivery.envelope.event.surfaceID.rawValue == surfaceID)
        #expect(delivery.envelope.event.kind == .approvalRequested)
    }

    @Test("rejects missing or malformed surface credentials")
    func invalidEnvironment() {
        let payload = Data(
            """
            {
              "session_id": "codex-session",
              "turn_id": "codex-turn",
              "hook_event_name": "Stop"
            }
            """.utf8
        )
        let base = [
            "MYTTY_EVENT_SOCKET": "/private/tmp/mytty.sock",
            "MYTTY_SURFACE_ID": "00000000-0000-0000-0000-000000000202",
            "MYTTY_EVENT_CAPABILITY": "surface-capability",
        ]
        var missingCapability = base
        missingCapability.removeValue(forKey: "MYTTY_EVENT_CAPABILITY")
        var invalidSurface = base
        invalidSurface["MYTTY_SURFACE_ID"] = "not-a-uuid"

        #expect(throws: AgentHookBridgeError.missingEnvironment(
            "MYTTY_EVENT_CAPABILITY"
        )) {
            try AgentHookBridge.makeDelivery(
                provider: .codex,
                payload: payload,
                environment: missingCapability,
                occurredAt: Date()
            )
        }
        #expect(throws: AgentHookBridgeError.invalidSurfaceIdentifier) {
            try AgentHookBridge.makeDelivery(
                provider: .codex,
                payload: payload,
                environment: invalidSurface,
                occurredAt: Date()
            )
        }
    }
}
