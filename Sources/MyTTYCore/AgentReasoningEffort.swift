import Foundation

/// The reasoning-effort level `agent spawn --reasoning-effort` can request
/// for a worker. Each provider CLI accepts a different subset, so the
/// raw values are the union and `isSupported(by:)` says which provider
/// takes which:
///
/// - Codex: `-c model_reasoning_effort=<value>` accepts minimal, low,
///   medium, high, xhigh.
/// - Claude Code: `--effort <value>` accepts low, medium, high, xhigh, max.
/// - Cursor: no reasoning-effort flag, so no value is supported.
public enum AgentReasoningEffort: String, Codable, CaseIterable, Equatable, Sendable {
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max

    /// The values the given provider's CLI accepts, in ascending effort.
    public static func supportedValues(
        for provider: AgentWorkerProvider
    ) -> [AgentReasoningEffort] {
        switch provider {
        case .codex: [.minimal, .low, .medium, .high, .xhigh]
        case .claude: [.low, .medium, .high, .xhigh, .max]
        case .cursor: []
        case .antigravity: [.low, .medium, .high, .xhigh, .max]
        }
    }

    public func isSupported(by provider: AgentWorkerProvider) -> Bool {
        Self.supportedValues(for: provider).contains(self)
    }
}
