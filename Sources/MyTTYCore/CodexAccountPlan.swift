import Foundation

/// Resolves a Codex account's subscription plan from `$CODEX_HOME/auth.json`
/// (falling back to `~/.codex/auth.json`). The plan lives inside
/// `tokens.id_token`, a JWT whose payload segment carries a
/// `chatgpt_plan_type` claim -- nested under the
/// `"https://api.openai.com/auth"` object, or occasionally top-level.
///
/// `auth.json` and the JWT it embeds are both untrusted, provider-owned
/// data: every step here tolerates a malformed shape by returning `nil`
/// rather than throwing, mirroring `CodexSessionInspector`'s tolerance of
/// malformed transcript lines.
public enum CodexAccountPlan {
    /// The JWT signature is never verified here -- the payload is only
    /// read for a display label -- so a hostile or corrupted token could
    /// otherwise claim an unbounded amount of memory. 64 KB is far more
    /// than any real `id_token` payload needs.
    private static let maximumPayloadBytes = 64 * 1_024

    public static func planName(
        homeDirectory: URL,
        environment: [String: String]
    ) -> String? {
        let authURL = codexHome(
            homeDirectory: homeDirectory,
            environment: environment
        )
        .appending(path: "auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let idToken = idToken(from: data),
              let payload = decodedPayload(from: idToken)
        else { return nil }
        return CodexPlanName.resolve(planType: planType(from: payload))
    }

    private static func codexHome(
        homeDirectory: URL,
        environment: [String: String]
    ) -> URL {
        if let configured = environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !configured.isEmpty
        {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
    }

    private static func idToken(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String,
              !idToken.isEmpty
        else { return nil }
        return idToken
    }

    private static func decodedPayload(from idToken: String) -> [String: Any]? {
        let segments = idToken.split(separator: ".", omittingEmptySubsequences: false)
        // Bound the encoded segment too, not just what it decodes to:
        // base64 decoding allocates before anyone can check the result.
        guard segments.count >= 2,
              segments[1].count <= maximumPayloadBytes,
              let decoded = base64URLDecode(String(segments[1])),
              decoded.count <= maximumPayloadBytes,
              let object = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any]
        else { return nil }
        return object
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        guard !value.isEmpty else { return nil }
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    private static func planType(from payload: [String: Any]) -> String? {
        if let auth = payload["https://api.openai.com/auth"] as? [String: Any],
           let planType = auth["chatgpt_plan_type"] as? String {
            return planType
        }
        return payload["chatgpt_plan_type"] as? String
    }
}
