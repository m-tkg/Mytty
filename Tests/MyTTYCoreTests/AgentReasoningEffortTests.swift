import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent reasoning effort")
struct AgentReasoningEffortTests {
    @Test("codex accepts minimal through xhigh but not max")
    func codexSupportedValues() {
        #expect(
            AgentReasoningEffort.supportedValues(for: .codex)
                == [.minimal, .low, .medium, .high, .xhigh]
        )
        #expect(!AgentReasoningEffort.max.isSupported(by: .codex))
    }

    @Test("claude accepts low through max but not minimal")
    func claudeSupportedValues() {
        #expect(
            AgentReasoningEffort.supportedValues(for: .claude)
                == [.low, .medium, .high, .xhigh, .max]
        )
        #expect(!AgentReasoningEffort.minimal.isSupported(by: .claude))
    }

    @Test("cursor has no reasoning-effort flag")
    func cursorSupportsNothing() {
        #expect(AgentReasoningEffort.supportedValues(for: .cursor).isEmpty)
        for effort in AgentReasoningEffort.allCases {
            #expect(!effort.isSupported(by: .cursor))
        }
    }
}
