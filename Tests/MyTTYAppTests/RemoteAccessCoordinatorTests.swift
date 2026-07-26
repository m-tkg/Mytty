import Foundation
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Remote host agent selection")
struct RemoteAccessCoordinatorTests {
    private func run(provider: AgentProvider) -> AgentRun {
        let events = [
            AgentEvent(
                id: AgentEventID(rawValue: UUID()),
                runID: AgentRunID(rawValue: UUID()),
                surfaceID: TerminalSurfaceID(),
                provider: provider,
                kind: .started,
                occurredAt: Date(timeIntervalSince1970: 0)
            ),
        ]
        return AgentEventReducer.reduce(events).values.first!
    }

    /// The bug this guards: a pane that once ran Cursor keeps Cursor runs
    /// in the event log, and a remote client would label the Claude Code
    /// now in the foreground with them.
    @Test("the detected foreground provider outranks a stale run")
    func detectedProviderOutranksStaleRun() {
        let selected = RemoteHostAgentSelection.select(
            detected: .claudeCode,
            latestRunForDetected: nil,
            mostRelevantRun: run(provider: .cursor)
        )
        #expect(selected.provider == .claudeCode)
        #expect(selected.run == nil)
    }

    @Test("the detected provider's own run supplies the state")
    func detectedProviderKeepsItsOwnRun() {
        let claudeRun = run(provider: .claudeCode)
        let selected = RemoteHostAgentSelection.select(
            detected: .claudeCode,
            latestRunForDetected: claudeRun,
            mostRelevantRun: run(provider: .cursor)
        )
        #expect(selected.provider == .claudeCode)
        #expect(selected.run == claudeRun)
    }

    /// No foreground agent detected (e.g. the process poll has not run
    /// yet, or a shell is in front): the event log remains the answer.
    @Test("without a detected provider the most relevant run wins")
    func fallsBackToMostRelevantRun() {
        let cursorRun = run(provider: .cursor)
        let selected = RemoteHostAgentSelection.select(
            detected: nil,
            latestRunForDetected: nil,
            mostRelevantRun: cursorRun
        )
        #expect(selected.provider == .cursor)
        #expect(selected.run == cursorRun)
    }

    @Test("no detection and no runs yields no agent")
    func nothingYieldsNothing() {
        let selected = RemoteHostAgentSelection.select(
            detected: nil,
            latestRunForDetected: nil,
            mostRelevantRun: nil
        )
        #expect(selected.provider == nil)
        #expect(selected.run == nil)
    }
}
