import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent integration installer")
struct AgentIntegrationInstallerTests {
    @Test("installs and removes Codex hooks without changing other handlers")
    func codexHooks() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let hooksURL = harness.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
        try harness.writeJSON(
            [
                "description": "keep this value",
                "hooks": [
                    "PermissionRequest": [
                        [
                            "_otty": true,
                            "hooks": [
                                [
                                    "type": "command",
                                    "command": "/Applications/Otty.app/hook",
                                ],
                            ],
                        ],
                    ],
                ],
            ],
            to: hooksURL
        )
        let installer = harness.installer

        #expect(try installer.status(for: .codex) == .notInstalled)
        try installer.install(.codex)
        let installedOnce = try harness.readJSON(hooksURL)
        try installer.install(.codex)
        let installedTwice = try harness.readJSON(hooksURL)

        #expect(try installer.status(for: .codex) == .installed)
        #expect(installedOnce as NSDictionary == installedTwice as NSDictionary)
        #expect(installedTwice["description"] as? String == "keep this value")
        #expect(
            harness.handlerCount(
                in: installedTwice,
                event: "SessionStart",
                commandContaining: "mytty-agent-hook' codex"
            ) == 1
        )
        #expect(
            harness.handlerCount(
                in: installedTwice,
                event: "PermissionRequest",
                commandContaining: "mytty-agent-hook' codex"
            ) == 1
        )
        #expect(
            harness.handlerCount(
                in: installedTwice,
                event: "UserPromptSubmit",
                commandContaining: "mytty-agent-hook' codex"
            ) == 1
        )
        #expect(
            harness.handlerCount(
                in: installedTwice,
                event: "Stop",
                commandContaining: "mytty-agent-hook' codex"
            ) == 1
        )
        #expect(
            harness.handlerCount(
                in: installedTwice,
                event: "PostToolUse",
                commandContaining: "mytty-agent-hook' codex"
            ) == 1
        )
        #expect(harness.handlerCount(
            in: installedTwice,
            event: "PermissionRequest",
            commandContaining: "/Applications/Otty.app/hook"
        ) == 1)
        #expect(FileManager.default.isExecutableFile(
            atPath: installer.installedHookExecutable.path
        ))

        try installer.remove(.codex)
        let removed = try harness.readJSON(hooksURL)

        #expect(try installer.status(for: .codex) == .notInstalled)
        #expect(removed["description"] as? String == "keep this value")
        #expect(harness.handlerCount(
            in: removed,
            event: "PermissionRequest",
            commandContaining: "/Applications/Otty.app/hook"
        ) == 1)
        #expect(harness.eventGroups(in: removed, event: "UserPromptSubmit").isEmpty)
        #expect(harness.eventGroups(in: removed, event: "Stop").isEmpty)
    }

    @Test("installs Claude Code hooks while preserving existing settings")
    func claudeCodeHooks() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let settingsURL = harness.home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
        try harness.writeJSON(
            [
                "model": "sonnet",
                "hooks": [
                    "PreToolUse": [
                        [
                            "matcher": "AskUserQuestion",
                            "hooks": [[
                                "type": "command",
                                "command": "afplay waiting.wav",
                            ]],
                        ],
                    ],
                ],
            ],
            to: settingsURL
        )
        let installer = harness.installer

        try installer.install(.claudeCode)
        try installer.install(.claudeCode)
        let installed = try harness.readJSON(settingsURL)

        #expect(try installer.status(for: .claudeCode) == .installed)
        #expect(installed["model"] as? String == "sonnet")
        #expect(harness.handlerCount(
            in: installed,
            event: "PreToolUse",
            commandContaining: "afplay waiting.wav"
        ) == 1)
        for event in [
            "SessionStart",
            "SessionEnd",
            "UserPromptSubmit",
            "PermissionRequest",
            "PostToolBatch",
            "Notification",
            "Stop",
            "StopFailure",
        ] {
            #expect(
                harness.execHandlerCount(
                    in: installed,
                    event: event,
                    executable: installer.installedHookExecutable.path,
                    argument: "claude-code"
                ) == 1
            )
        }

        try installer.remove(.claudeCode)
        let removed = try harness.readJSON(settingsURL)

        #expect(try installer.status(for: .claudeCode) == .notInstalled)
        #expect(removed["model"] as? String == "sonnet")
        #expect(harness.handlerCount(
            in: removed,
            event: "PreToolUse",
            commandContaining: "afplay waiting.wav"
        ) == 1)
    }

    @Test("owns only its OpenCode plugin file")
    func openCodePlugin() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let pluginDirectory = harness.home
            .appendingPathComponent(".config/opencode/plugins", isDirectory: true)
        let pluginURL = pluginDirectory.appendingPathComponent("mytty.js")
        let unrelatedURL = pluginDirectory.appendingPathComponent("other.js")
        try FileManager.default.createDirectory(
            at: pluginDirectory,
            withIntermediateDirectories: true
        )
        try "export const Other = {}\n".write(
            to: unrelatedURL,
            atomically: true,
            encoding: .utf8
        )
        let installer = harness.installer

        try installer.install(.openCode)
        let installedOnce = try String(contentsOf: pluginURL, encoding: .utf8)
        try installer.install(.openCode)
        let installedTwice = try String(contentsOf: pluginURL, encoding: .utf8)

        #expect(try installer.status(for: .openCode) == .installed)
        #expect(installedOnce == installedTwice)
        #expect(installedOnce.contains("permission.asked"))
        #expect(installedOnce.contains("permission.replied"))
        #expect(installedOnce.contains("question.asked"))
        #expect(installedOnce.contains("session.idle"))
        #expect(installedOnce.contains("session.error"))
        #expect(installedOnce.contains(installer.installedHookExecutable.path))

        try installer.remove(.openCode)

        #expect(try installer.status(for: .openCode) == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: pluginURL.path))
        #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }

    @Test("owns an Antigravity plugin without changing other plugins")
    func antigravityPlugin() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let pluginsDirectory = harness.home
            .appendingPathComponent(".gemini/config/plugins", isDirectory: true)
        let pluginDirectory = pluginsDirectory
            .appendingPathComponent("mytty", isDirectory: true)
        let manifestURL = pluginDirectory.appendingPathComponent("plugin.json")
        let hooksURL = pluginDirectory.appendingPathComponent("hooks.json")
        let unrelatedURL = pluginsDirectory
            .appendingPathComponent("other/plugin.json")
        try harness.writeJSON(["name": "other"], to: unrelatedURL)
        let installer = harness.installer

        try installer.install(.antigravity)
        let firstHooks = try harness.readJSON(hooksURL)
        try installer.install(.antigravity)
        let secondHooks = try harness.readJSON(hooksURL)

        #expect(try installer.status(for: .antigravity) == .installed)
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
        #expect(firstHooks as NSDictionary == secondHooks as NSDictionary)
        let definition = try #require(
            secondHooks["mytty-attention"] as? [String: Any]
        )
        for event in ["PreInvocation", "PostInvocation", "Stop"] {
            let handlers = try #require(definition[event] as? [[String: Any]])
            #expect(handlers.count == 1)
            #expect(
                (handlers[0]["command"] as? String)?
                    .contains("mytty-agent-hook' antigravity") == true
            )
        }

        try installer.remove(.antigravity)

        #expect(try installer.status(for: .antigravity) == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: pluginDirectory.path))
        #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }

    @Test("merges Cursor hooks without changing other handlers")
    func cursorHooks() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let hooksURL = harness.home
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("hooks.json")
        try harness.writeJSON(
            [
                "version": 1,
                "hooks": [
                    "stop": [["command": "./hooks/metrics.sh"]],
                ],
            ],
            to: hooksURL
        )
        let installer = harness.installer

        try installer.install(.cursor)
        let installedOnce = try harness.readJSON(hooksURL)
        try installer.install(.cursor)
        let installedTwice = try harness.readJSON(hooksURL)

        #expect(try installer.status(for: .cursor) == .installed)
        #expect(installedOnce as NSDictionary == installedTwice as NSDictionary)
        #expect(installedTwice["version"] as? Int == 1)
        for event in [
            "beforeSubmitPrompt",
            "postToolUse",
            "postToolUseFailure",
            "stop",
        ] {
            #expect(
                harness.directHandlerCount(
                    in: installedTwice,
                    event: event,
                    commandContaining: "mytty-agent-hook' cursor"
                ) == 1
            )
        }
        #expect(
            harness.directHandlerCount(
                in: installedTwice,
                event: "stop",
                commandContaining: "./hooks/metrics.sh"
            ) == 1
        )

        try installer.remove(.cursor)
        let removed = try harness.readJSON(hooksURL)

        #expect(try installer.status(for: .cursor) == .notInstalled)
        #expect(
            harness.directHandlerCount(
                in: removed,
                event: "stop",
                commandContaining: "./hooks/metrics.sh"
            ) == 1
        )
        #expect(
            harness.directHandlerCount(
                in: removed,
                event: "beforeSubmitPrompt",
                commandContaining: "mytty-agent-hook' cursor"
            ) == 0
        )
    }

    @Test("does not overwrite malformed provider configuration")
    func malformedConfiguration() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let settingsURL = harness.home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let malformed = Data("{ not-json\n".utf8)
        try malformed.write(to: settingsURL)

        #expect(throws: AgentIntegrationInstallerError.invalidConfiguration(
            settingsURL.path
        )) {
            try harness.installer.install(.claudeCode)
        }
        #expect(try Data(contentsOf: settingsURL) == malformed)
    }

    @Test("reports a partial installation as needing repair")
    func repairStatus() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let installer = harness.installer
        try installer.install(.codex)
        let hooksURL = harness.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
        var configuration = try harness.readJSON(hooksURL)
        var hooks = try #require(configuration["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "Stop")
        configuration["hooks"] = hooks
        try harness.writeJSON(configuration, to: hooksURL)

        #expect(try installer.status(for: .codex) == .needsRepair)
    }

    @Test("repairs an installed hook helper after the app updates")
    func outdatedHookHelper() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let installer = harness.installer
        try installer.install(.claudeCode)
        let updatedHelper = Data("updated helper".utf8)
        try updatedHelper.write(to: harness.sourceExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: harness.sourceExecutable.path
        )

        #expect(try installer.status(for: .claudeCode) == .needsRepair)

        try installer.install(.claudeCode)

        #expect(try installer.status(for: .claudeCode) == .installed)
        #expect(
            try Data(contentsOf: installer.installedHookExecutable)
                == updatedHelper
        )
    }
}

private struct Harness {
    let root: URL
    let home: URL
    let applicationSupport: URL
    let sourceExecutable: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        applicationSupport = home
            .appendingPathComponent("Library/Application Support/mytty", isDirectory: true)
        sourceExecutable = root
            .appendingPathComponent("source", isDirectory: true)
            .appendingPathComponent("mytty-agent-hook")
        try FileManager.default.createDirectory(
            at: sourceExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test helper".utf8).write(to: sourceExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: sourceExecutable.path
        )
    }

    var installer: AgentIntegrationInstaller {
        AgentIntegrationInstaller(
            homeDirectory: home,
            applicationSupportDirectory: applicationSupport,
            sourceHookExecutable: sourceExecutable
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url)
    }

    func readJSON(_ url: URL) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        )
        return try #require(object as? [String: Any])
    }

    func eventGroups(
        in configuration: [String: Any],
        event: String
    ) -> [[String: Any]] {
        let hooks = configuration["hooks"] as? [String: Any]
        return hooks?[event] as? [[String: Any]] ?? []
    }

    func handlerCount(
        in configuration: [String: Any],
        event: String,
        commandContaining fragment: String
    ) -> Int {
        eventGroups(in: configuration, event: event)
            .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .filter {
                ($0["command"] as? String)?.contains(fragment) == true
            }
            .count
    }

    func execHandlerCount(
        in configuration: [String: Any],
        event: String,
        executable: String,
        argument: String
    ) -> Int {
        eventGroups(in: configuration, event: event)
            .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .filter {
                $0["command"] as? String == executable
                    && $0["args"] as? [String] == [argument]
            }
            .count
    }

    func directHandlerCount(
        in configuration: [String: Any],
        event: String,
        commandContaining fragment: String
    ) -> Int {
        eventGroups(in: configuration, event: event)
            .filter {
                ($0["command"] as? String)?.contains(fragment) == true
            }
            .count
    }
}
