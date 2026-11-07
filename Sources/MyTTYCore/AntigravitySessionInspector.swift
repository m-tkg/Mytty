import Foundation

/// Reads the model and remaining context for an Antigravity session.
/// Antigravity's conversation database is protobuf-encoded and not
/// structurally parseable, so the per-session numbers come from the
/// snapshot that mytty's `statusLine` command records (model and context
/// window, see `AntigravityStatusLineStore`). Without a snapshot -- the
/// status line isn't installed yet, or agy hasn't refreshed it -- this
/// falls back to the globally selected model in the settings file, which
/// is best-effort and carries no context figure. A hook session ID is
/// required either way, to avoid attributing the global setting to a pane
/// that isn't actually running Antigravity.
public enum AntigravitySessionInspector {
    public static func status(
        sessionID: String?,
        antigravityHome: URL = defaultAntigravityHome,
        statusLine: AntigravityStatusLineStore? = nil
    ) -> AgentSessionStatus? {
        guard let sessionID = AgentSessionValidation.identifier(sessionID)
        else { return nil }
        let snapshot = statusLine?.snapshot(sessionID: sessionID)
        guard let modelName = snapshot?.modelName ?? currentModelName(
            settingsURL: antigravityHome
                .appendingPathComponent("settings.json")
        ) else { return nil }
        return AgentSessionStatus(
            sessionID: sessionID,
            modelName: modelName,
            contextRemainingPercent: snapshot?.contextRemainingPercent
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
