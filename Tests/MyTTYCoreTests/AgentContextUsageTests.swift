import Testing

@testable import MyTTYCore

@Suite("Agent context usage")
struct AgentContextUsageTests {
    @Test("rounds the used share and subtracts it from 100")
    func roundsUsedShare() {
        // 45.903% used -> 46% used -> 54% remaining.
        #expect(AgentContextUsage.remainingPercent(used: 91_806, total: 200_000) == 54)
        // 0.5% used rounds up to 1% used -> 99% remaining (not 99.5).
        #expect(AgentContextUsage.remainingPercent(used: 5, total: 1_000) == 99)
        #expect(AgentContextUsage.remainingPercent(used: 0, total: 200_000) == 100)
    }

    @Test("clamps to 0...100")
    func clamps() {
        #expect(AgentContextUsage.remainingPercent(used: 500_000, total: 200_000) == 0)
        #expect(AgentContextUsage.remainingPercent(used: -10, total: 200_000) == 100)
    }

    @Test("returns nil without a usable window or usage")
    func unknown() {
        #expect(AgentContextUsage.remainingPercent(used: 10, total: 0) == nil)
        #expect(AgentContextUsage.remainingPercent(used: 10, total: -5) == nil)
        #expect(AgentContextUsage.remainingPercent(used: .nan, total: 100) == nil)
        #expect(AgentContextUsage.remainingPercent(used: 10, total: .infinity) == nil)
    }
}
