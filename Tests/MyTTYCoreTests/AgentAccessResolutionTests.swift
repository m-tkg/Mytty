import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent access resolution")
struct AgentAccessResolutionTests {
    @Test("an explicit access policy always wins, same provider or not")
    func explicitAccessWins() {
        #expect(AgentAccessResolution.resolve(
            requestedAccess: .review,
            workerProviderMatchesAnchor: true
        ) == .review)
        #expect(AgentAccessResolution.resolve(
            requestedAccess: .review,
            workerProviderMatchesAnchor: false
        ) == .review)
        #expect(AgentAccessResolution.resolve(
            requestedAccess: .workspaceWrite,
            workerProviderMatchesAnchor: true
        ) == .workspaceWrite)
        #expect(AgentAccessResolution.resolve(
            requestedAccess: .inherit,
            workerProviderMatchesAnchor: false
        ) == .inherit)
    }

    @Test("no access, same provider as anchor -> inherit")
    func noAccessSameProviderInherits() {
        #expect(AgentAccessResolution.resolve(
            requestedAccess: nil,
            workerProviderMatchesAnchor: true
        ) == .inherit)
    }

    @Test("no access, different provider than anchor -> workspace-write")
    func noAccessDifferentProviderFallsBackToWorkspaceWrite() {
        #expect(AgentAccessResolution.resolve(
            requestedAccess: nil,
            workerProviderMatchesAnchor: false
        ) == .workspaceWrite)
    }
}
