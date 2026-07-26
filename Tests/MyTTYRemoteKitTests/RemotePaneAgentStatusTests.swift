import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite
struct RemotePaneAgentStatusTests {
    @Test
    func roundTripsEveryField() throws {
        let status = RemotePaneAgentStatus(
            provider: "claude-code",
            state: "waiting-approval",
            modelName: "Opus",
            contextRemainingPercent: 42.5,
            needsAttention: true
        )
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(
            RemotePaneAgentStatus.self,
            from: data
        )
        #expect(decoded == status)
    }

    @Test
    func omitsEveryAbsentFieldFromTheWire() throws {
        let data = try JSONEncoder().encode(RemotePaneAgentStatus())
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        // An all-empty status must not cost a byte per pane on a snapshot
        // that carries one of these for every pane.
        #expect(object.isEmpty)
    }

    @Test
    func decodesAnEmptyObjectAsNoAgent() throws {
        let decoded = try JSONDecoder().decode(
            RemotePaneAgentStatus.self,
            from: Data("{}".utf8)
        )
        #expect(decoded == RemotePaneAgentStatus())
        #expect(decoded.isEmpty)
        #expect(!decoded.needsAttention)
    }

    @Test
    func isEmptyOnlyWhenNothingIsWorthShowing() {
        #expect(RemotePaneAgentStatus().isEmpty)
        #expect(!RemotePaneAgentStatus(provider: "codex").isEmpty)
        #expect(!RemotePaneAgentStatus(needsAttention: true).isEmpty)
        #expect(
            !RemotePaneAgentStatus(contextRemainingPercent: 0).isEmpty
        )
    }

    @Test
    func paneFromAnOlderHostDecodesWithoutAnAgent() throws {
        // Hosts before protocol version 5 send no `agent` key at all; a
        // client must read that as "no agent status", not fail to decode.
        let json = """
        {"id":"p1","title":"t","command":"zsh","location":"/tmp",
         "kind":"terminal","isActive":true}
        """
        let pane = try JSONDecoder().decode(
            RemotePane.self,
            from: Data(json.utf8)
        )
        #expect(pane.agent == nil)
        #expect(pane.id == "p1")
    }

    @Test
    func paneRoundTripsItsAgentStatus() throws {
        let pane = RemotePane(
            id: "p1",
            title: "t",
            command: "codex",
            location: "/tmp",
            kind: .terminal,
            isActive: false,
            agent: RemotePaneAgentStatus(
                provider: "codex",
                state: "running",
                needsAttention: false
            )
        )
        let data = try JSONEncoder().encode(pane)
        let decoded = try JSONDecoder().decode(RemotePane.self, from: data)
        #expect(decoded == pane)
    }
}
