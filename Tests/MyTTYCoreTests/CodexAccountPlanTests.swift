import Foundation
import Testing

@testable import MyTTYCore

@Suite("Codex account plan")
struct CodexAccountPlanTests {
    @Test("resolves the plan from a hand-rolled unsigned JWT id_token")
    func resolvesPlanFromAuthFile() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeAuthFile(
            in: root,
            idToken: Self.makeIDToken(claims: [
                "https://api.openai.com/auth": ["chatgpt_plan_type": "pro"],
            ])
        )

        #expect(
            CodexAccountPlan.planName(
                homeDirectory: FileManager.default.temporaryDirectory,
                environment: ["CODEX_HOME": root.path]
            ) == "Pro"
        )
    }

    @Test("falls back to a top-level chatgpt_plan_type claim")
    func resolvesTopLevelPlanClaim() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeAuthFile(
            in: root,
            idToken: Self.makeIDToken(claims: ["chatgpt_plan_type": "team"])
        )

        #expect(
            CodexAccountPlan.planName(
                homeDirectory: FileManager.default.temporaryDirectory,
                environment: ["CODEX_HOME": root.path]
            ) == "Team"
        )
    }

    @Test("CODEX_HOME takes precedence over homeDirectory/.codex")
    func codexHomeTakesPrecedence() throws {
        let home = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let defaultCodexHome = home.appending(path: ".codex", directoryHint: .isDirectory)
        try Self.writeAuthFile(
            in: defaultCodexHome,
            idToken: Self.makeIDToken(claims: [
                "https://api.openai.com/auth": ["chatgpt_plan_type": "free"],
            ])
        )

        let overrideRoot = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: overrideRoot) }
        try Self.writeAuthFile(
            in: overrideRoot,
            idToken: Self.makeIDToken(claims: [
                "https://api.openai.com/auth": ["chatgpt_plan_type": "enterprise"],
            ])
        )

        #expect(
            CodexAccountPlan.planName(
                homeDirectory: home,
                environment: ["CODEX_HOME": overrideRoot.path]
            ) == "Enterprise"
        )
        // No CODEX_HOME (or an empty one): falls back to homeDirectory/.codex.
        #expect(
            CodexAccountPlan.planName(
                homeDirectory: home,
                environment: [:]
            ) == "Free"
        )
        #expect(
            CodexAccountPlan.planName(
                homeDirectory: home,
                environment: ["CODEX_HOME": "  "]
            ) == "Free"
        )
    }

    @Test("returns nil when auth.json is missing")
    func missingFile() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(
            CodexAccountPlan.planName(
                homeDirectory: FileManager.default.temporaryDirectory,
                environment: ["CODEX_HOME": root.path]
            ) == nil
        )
    }

    @Test("returns nil for malformed JSON in auth.json")
    func malformedJSON() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not json".utf8).write(
            to: root.appending(path: "auth.json")
        )

        #expect(
            CodexAccountPlan.planName(
                homeDirectory: FileManager.default.temporaryDirectory,
                environment: ["CODEX_HOME": root.path]
            ) == nil
        )
    }

    @Test("returns nil when id_token is not a JWT")
    func nonJWTIDToken() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeAuthFile(in: root, idToken: "not-a-jwt")

        #expect(
            CodexAccountPlan.planName(
                homeDirectory: FileManager.default.temporaryDirectory,
                environment: ["CODEX_HOME": root.path]
            ) == nil
        )
    }

    @Test("returns nil when the JWT payload has no plan claim")
    func noPlanClaim() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeAuthFile(
            in: root,
            idToken: Self.makeIDToken(claims: ["sub": "user-123"])
        )

        #expect(
            CodexAccountPlan.planName(
                homeDirectory: FileManager.default.temporaryDirectory,
                environment: ["CODEX_HOME": root.path]
            ) == nil
        )
    }

    @Test("returns nil when tokens.id_token is missing entirely")
    func missingIDToken() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"tokens":{}}"#.utf8).write(
            to: root.appending(path: "auth.json")
        )

        #expect(
            CodexAccountPlan.planName(
                homeDirectory: FileManager.default.temporaryDirectory,
                environment: ["CODEX_HOME": root.path]
            ) == nil
        )
    }

    // MARK: - Fixtures

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private static func writeAuthFile(in directory: URL, idToken: String) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let object: [String: Any] = ["tokens": ["id_token": idToken]]
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: directory.appending(path: "auth.json"))
    }

    /// Builds an unsigned JWT-shaped string: nothing verifies the
    /// signature, so a base64url-encoded JSON payload sandwiched between
    /// two arbitrary segments is enough.
    private static func makeIDToken(claims: [String: Any]) -> String {
        let payloadData = try! JSONSerialization.data(withJSONObject: claims)
        let payload = base64URLEncode(payloadData)
        return "header.\(payload).signature"
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
