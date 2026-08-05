import Foundation

/// Resolves `agent spawn`'s effective access policy from what the caller
/// actually asked for. `ControlRequest.spawnAgent`'s `access` field is
/// optional specifically so a caller who never mentions `--access` can be
/// told apart from one who explicitly asked for `workspace-write` — the
/// two now resolve differently. See `ControlRequest.spawnAgent`'s doc
/// comment for the full resolution order this implements: explicit access
/// wins outright; absent access falls back to `.inherit` only when the
/// worker's provider matches the anchor pane's current foreground
/// provider (mirroring `AgentAccessPolicy.inherit`'s own "same provider"
/// requirement); otherwise it's `.workspaceWrite`, exactly the default an
/// omitted `--access` already produced before this resolution existed.
///
/// Pure and Foundation-only, mirroring how `AgentIntegrationPreflight` was
/// pulled out of `AgentJobCoordinator` for the same reason: this decision
/// needs no app state, so it stays covered by a fast unit test independent
/// of `TerminalWindowController`/`WindowSessionCoordinator` wiring.
public enum AgentAccessResolution {
    public static func resolve(
        requestedAccess: AgentAccessPolicy?,
        workerProviderMatchesAnchor: Bool
    ) -> AgentAccessPolicy {
        if let requestedAccess {
            return requestedAccess
        }
        return workerProviderMatchesAnchor ? .inherit : .workspaceWrite
    }
}
