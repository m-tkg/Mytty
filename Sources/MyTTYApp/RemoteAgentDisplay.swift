import MyTTYCore
import MyTTYRemoteKit

/// Turns the raw provider identifier a host puts on the wire back into the
/// name Mytty shows for it locally.
///
/// The wire carries `AgentProvider`'s raw value rather than a display name
/// so the host never has to know the client's language. An unrecognized
/// identifier is passed through untouched: a newer host may know a provider
/// this build does not, and showing its identifier beats showing nothing.
enum RemoteAgentDisplay {
    static func providerName(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        guard let provider = AgentProvider(rawValue: rawValue) else {
            return rawValue
        }
        return TerminalWindowTitle.name(for: provider)
    }
}
