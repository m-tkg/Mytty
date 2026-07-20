import Foundation

/// Reads Antigravity's globally selected model from its settings file.
/// Antigravity's conversation database is protobuf-encoded and not
/// structurally parseable, and the settings file records only the
/// currently selected model rather than a per-session value, so this is
/// best-effort: it requires a hook session ID (to avoid attributing the
/// global setting to a pane that isn't actually running Antigravity) and
/// `contextRemainingPercent` is always `nil`.
public enum AntigravitySessionInspector {
    public static func status(
        sessionID: String?,
        antigravityHome: URL = defaultAntigravityHome
    ) -> AgentSessionStatus? {
        guard let sessionID = AgentSessionValidation.identifier(sessionID)
        else { return nil }
        guard let modelName = currentModelName(
            settingsURL: antigravityHome
                .appendingPathComponent("settings.json")
        ) else { return nil }
        return AgentSessionStatus(
            sessionID: sessionID,
            modelName: modelName,
            contextRemainingPercent: nil
        )
    }

    public static var defaultAntigravityHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                ".gemini/antigravity-cli",
                isDirectory: true
            )
    }

    static func currentModelName(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        else { return nil }
        return AgentSessionValidation.label(object["model"] as? String)
    }

    private static func currentModelName(settingsURL: URL) -> String? {
        guard let data = try? Data(contentsOf: settingsURL) else {
            return nil
        }
        return currentModelName(from: data)
    }
}
