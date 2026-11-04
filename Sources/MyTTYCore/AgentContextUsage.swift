import Foundation

/// Shared context-meter arithmetic for the provider inspectors.
enum AgentContextUsage {
    /// Percentage of the context window still free, `nil` when the window
    /// or the usage is not a usable number.
    ///
    /// Claude Code rounds the *used* share to a whole percent and subtracts
    /// it, so rounding the remainder instead would report one percent more
    /// than the CLI does on half-percent usage. Every provider follows that
    /// convention.
    static func remainingPercent(used: Double, total: Double) -> Double? {
        guard used.isFinite, total.isFinite, total > 0 else { return nil }
        return 100 - min(100, max(0, (used / total * 100).rounded()))
    }
}
