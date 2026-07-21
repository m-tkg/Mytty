import Foundation

public enum AgentHookBridgeError: Error, Equatable, Sendable {
    case missingEnvironment(String)
    case invalidSurfaceIdentifier
    case invalidSocketPath
}

public struct AgentHookDelivery: Equatable, Sendable {
    public let socketURL: URL
    public let envelope: AgentEventEnvelope

    public init(socketURL: URL, envelope: AgentEventEnvelope) {
        self.socketURL = socketURL
        self.envelope = envelope
    }
}

public enum AgentHookBridge {
    public static let socketEnvironmentKey = "MYTTY_EVENT_SOCKET"
    public static let surfaceEnvironmentKey = "MYTTY_SURFACE_ID"
    public static let capabilityEnvironmentKey = "MYTTY_EVENT_CAPABILITY"
    /// Not a hook-delivery field — every Mytty pane's shell gets this env
    /// var too (see `AgentEventServer.environment(for:)`), so `mytty-ctl`
    /// can find the AI control socket the same way `mytty-agent-hook`
    /// finds `socketEnvironmentKey`, without recomputing
    /// `ApplicationPaths` and risking a release/dev mismatch. Named here
    /// alongside the other pane environment keys rather than in a new
    /// type, since callers already import `AgentHookBridge` for this.
    public static let controlSocketEnvironmentKey = "MYTTY_CONTROL_SOCKET"
    /// Absolute path to the installed `mytty-ctl` binary (see
    /// `AgentIntegrationInstaller.installedHookExecutable` for the same
    /// pattern applied to `mytty-agent-hook`), so AI tooling in a pane can
    /// invoke it without needing it on `PATH`.
    public static let controlExecutableEnvironmentKey = "MYTTY_CTL_BIN"
    /// The standard `PATH` variable — set here (not just `MYTTY_CTL_BIN`)
    /// so a bare `mytty-ctl` also resolves in every Mytty pane. See
    /// `paneSearchPath(appending:to:)`.
    public static let searchPathEnvironmentKey = "PATH"

    /// Appends `directory` to `existingPath` (colon-joined, skipped if
    /// already present) so a pane's shell can find a binary that lives
    /// outside whatever directories macOS or the user's dotfiles already
    /// search. This mirrors what Ghostty's own core already does for its
    /// own binary directory (`Vendor/ghostty/src/termio/Exec.zig`,
    /// "appending ghostty bin to path") — append, don't prepend, so
    /// anything the user already has earlier in `PATH` still wins.
    public static func paneSearchPath(
        appending directory: String,
        to existingPath: String?
    ) -> String {
        guard !directory.isEmpty else { return existingPath ?? "" }
        guard let existingPath, !existingPath.isEmpty else {
            return directory
        }
        let components = existingPath.split(
            separator: ":",
            omittingEmptySubsequences: true
        )
        if components.contains(Substring(directory)) {
            return existingPath
        }
        return existingPath + ":" + directory
    }

    public static func makeDelivery(
        provider: AgentProvider,
        payload: Data,
        environment: [String: String],
        occurredAt: Date
    ) throws -> AgentHookDelivery? {
        guard let socketPath = environment[socketEnvironmentKey],
              !socketPath.isEmpty
        else { return nil }
        guard socketPath.hasPrefix("/") else {
            throw AgentHookBridgeError.invalidSocketPath
        }
        let surfaceValue = try requiredValue(
            surfaceEnvironmentKey,
            in: environment
        )
        guard let surfaceUUID = UUID(uuidString: surfaceValue) else {
            throw AgentHookBridgeError.invalidSurfaceIdentifier
        }
        let capability = try requiredValue(
            capabilityEnvironmentKey,
            in: environment
        )

        guard let event = try AgentHookEventAdapter.makeEvent(
            provider: provider,
            payload: payload,
            surfaceID: TerminalSurfaceID(rawValue: surfaceUUID),
            occurredAt: occurredAt
        ) else { return nil }

        return AgentHookDelivery(
            socketURL: URL(fileURLWithPath: socketPath),
            envelope: AgentEventEnvelope(
                capability: capability,
                event: event
            )
        )
    }

    private static func requiredValue(
        _ key: String,
        in environment: [String: String]
    ) throws -> String {
        guard let value = environment[key], !value.isEmpty else {
            throw AgentHookBridgeError.missingEnvironment(key)
        }
        return value
    }
}
