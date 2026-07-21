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
            "preToolUse",
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

        let hooks = try #require(installedTwice["hooks"] as? [String: Any])
        let preToolUseHandlers = try #require(
            hooks["preToolUse"] as? [[String: Any]]
        )
        let ownedHandler = try #require(
            preToolUseHandlers.first {
                ($0["command"] as? String)?
                    .contains("mytty-agent-hook' cursor") == true
            }
        )
        #expect(ownedHandler["type"] as? String == "command")

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

    @Test("replaces an old beforeShellExecution/afterShellExecution Cursor install with preToolUse")
    func cursorHooksMigrateFromShellExecutionHandlers() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let hooksURL = harness.home
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("hooks.json")
        let installer = harness.installer
        let ownedCommand =
            "'\(installer.installedHookExecutable.path)' cursor"

        // Simulates a config left behind by the prior (PR #10) install,
        // which registered mytty's own handler on beforeShellExecution
        // and afterShellExecution.
        try harness.writeJSON(
            [
                "version": 1,
                "hooks": [
                    "beforeShellExecution": [
                        ["type": "command", "command": ownedCommand],
                    ],
                    "afterShellExecution": [
                        ["type": "command", "command": ownedCommand],
                    ],
                    "stop": [
                        ["type": "command", "command": ownedCommand],
                        ["type": "command", "command": "./hooks/metrics.sh"],
                    ],
                ],
            ],
            to: hooksURL
        )

        try installer.install(.cursor)
        let installed = try harness.readJSON(hooksURL)

        #expect(try installer.status(for: .cursor) == .installed)
        #expect(harness.eventGroups(in: installed, event: "beforeShellExecution").isEmpty)
        #expect(harness.eventGroups(in: installed, event: "afterShellExecution").isEmpty)
        #expect(
            harness.directHandlerCount(
                in: installed,
                event: "preToolUse",
                commandContaining: "mytty-agent-hook' cursor"
            ) == 1
        )
        #expect(
            harness.directHandlerCount(
                in: installed,
                event: "stop",
                commandContaining: "mytty-agent-hook' cursor"
            ) == 1
        )
        #expect(
            harness.directHandlerCount(
                in: installed,
                event: "stop",
                commandContaining: "./hooks/metrics.sh"
            ) == 1
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

    @Test("writes a Claude Code pane-team skill Mytty owns outright")
    func paneTeamPointerClaudeCode() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let skillURL = harness.home
            .appendingPathComponent(".claude/skills/mytty-panes", isDirectory: true)
            .appendingPathComponent("SKILL.md")
        let unrelatedSkillURL = harness.home
            .appendingPathComponent(".claude/skills/other-skill", isDirectory: true)
            .appendingPathComponent("SKILL.md")
        try FileManager.default.createDirectory(
            at: unrelatedSkillURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "other skill\n".write(
            to: unrelatedSkillURL,
            atomically: true,
            encoding: .utf8
        )
        let installer = harness.installer

        #expect(
            try installer.paneTeamPointerStatus(
                for: .claudeCode,
                language: .english
            ) == .notInstalled
        )
        try installer.installPaneTeamPointer(.claudeCode, language: .english)
        let installedOnce = try String(contentsOf: skillURL, encoding: .utf8)
        try installer.installPaneTeamPointer(.claudeCode, language: .english)
        let installedTwice = try String(contentsOf: skillURL, encoding: .utf8)

        #expect(
            try installer.paneTeamPointerStatus(
                for: .claudeCode,
                language: .english
            ) == .installed
        )
        #expect(installedOnce == installedTwice)
        #expect(installedOnce.contains("name: mytty-panes"))
        #expect(installedOnce.contains("$MYTTY_CTL_BIN\" guide"))

        try installer.removePaneTeamPointer(.claudeCode)

        #expect(
            try installer.paneTeamPointerStatus(
                for: .claudeCode,
                language: .english
            ) == .notInstalled
        )
        #expect(!FileManager.default.fileExists(atPath: skillURL.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: skillURL.deletingLastPathComponent().path
            )
        )
        #expect(FileManager.default.fileExists(atPath: unrelatedSkillURL.path))
    }

    @Test("reports a changed Claude Code pane-team skill as needing repair")
    func paneTeamPointerClaudeCodeRepair() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let skillURL = harness.home
            .appendingPathComponent(".claude/skills/mytty-panes", isDirectory: true)
            .appendingPathComponent("SKILL.md")
        let installer = harness.installer
        try installer.installPaneTeamPointer(.claudeCode, language: .english)
        try "stale content\n".write(
            to: skillURL,
            atomically: true,
            encoding: .utf8
        )

        #expect(
            try installer.paneTeamPointerStatus(
                for: .claudeCode,
                language: .english
            ) == .needsRepair
        )

        try installer.installPaneTeamPointer(.claudeCode, language: .english)

        #expect(
            try installer.paneTeamPointerStatus(
                for: .claudeCode,
                language: .english
            ) == .installed
        )
    }

    @Test("reports the pane-team pointer as needing repair after the app language changes, and repair rewrites it in the new language")
    func paneTeamPointerLanguageSwitchNeedsRepairThenRewrites() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let skillURL = harness.home
            .appendingPathComponent(".claude/skills/mytty-panes", isDirectory: true)
            .appendingPathComponent("SKILL.md")
        let agentsURL = harness.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("AGENTS.md")
        let installer = harness.installer

        try installer.installPaneTeamPointer(.claudeCode, language: .english)
        try installer.installPaneTeamPointer(.codex, language: .english)

        #expect(
            try installer.paneTeamPointerStatus(
                for: .claudeCode,
                language: .english
            ) == .installed
        )
        #expect(
            try installer.paneTeamPointerStatus(
                for: .codex,
                language: .english
            ) == .installed
        )

        // Switching the app's language without touching the files:
        // English content is still on disk, so it now reads as needing
        // repair against Japanese, and as still installed against English.
        #expect(
            try installer.paneTeamPointerStatus(
                for: .claudeCode,
                language: .japanese
            ) == .needsRepair
        )
        #expect(
            try installer.paneTeamPointerStatus(
                for: .codex,
                language: .japanese
            ) == .needsRepair
        )
        #expect(
            try installer.paneTeamPointerStatus(
                for: .claudeCode,
                language: .english
            ) == .installed
        )

        try installer.installPaneTeamPointer(.claudeCode, language: .japanese)
        try installer.installPaneTeamPointer(.codex, language: .japanese)

        #expect(
            try installer.paneTeamPointerStatus(
                for: .claudeCode,
                language: .japanese
            ) == .installed
        )
        #expect(
            try installer.paneTeamPointerStatus(
                for: .codex,
                language: .japanese
            ) == .installed
        )
        let claudeSkill = try String(contentsOf: skillURL, encoding: .utf8)
        #expect(claudeSkill.contains("name: mytty-panes"))
        #expect(claudeSkill.contains("$MYTTY_CTL_BIN\" guide"))
        #expect(claudeSkill.contains("ペイン"))
        let agentsBody = try String(contentsOf: agentsURL, encoding: .utf8)
        #expect(agentsBody.contains("<!-- mytty:pane-team:begin -->"))
        #expect(agentsBody.contains("<!-- mytty:pane-team:end -->"))
        #expect(agentsBody.contains("ペイン"))
        // The block marker stays the same across languages -- overwriting a
        // Japanese block with an English one (or vice versa) must not
        // duplicate it.
        #expect(
            agentsBody.components(
                separatedBy: "<!-- mytty:pane-team:begin -->"
            ).count == 2
        )

        try installer.installPaneTeamPointer(.codex, language: .english)
        let agentsBodyAfterEnglishOverwrite = try String(
            contentsOf: agentsURL,
            encoding: .utf8
        )
        #expect(
            agentsBodyAfterEnglishOverwrite.components(
                separatedBy: "<!-- mytty:pane-team:begin -->"
            ).count == 2
        )
        #expect(!agentsBodyAfterEnglishOverwrite.contains("ペイン"))
    }

    @Test("appends a managed Codex AGENTS.md block without touching the rest")
    func paneTeamPointerCodexAppendsToExistingFile() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let agentsURL = harness.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("AGENTS.md")
        try FileManager.default.createDirectory(
            at: agentsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existingBody = "# My project instructions\n\nKeep it terse.\n"
        try existingBody.write(to: agentsURL, atomically: true, encoding: .utf8)
        let installer = harness.installer

        #expect(
            try installer.paneTeamPointerStatus(for: .codex, language: .english)
                == .notInstalled
        )
        try installer.installPaneTeamPointer(.codex, language: .english)
        let installedOnce = try String(contentsOf: agentsURL, encoding: .utf8)
        try installer.installPaneTeamPointer(.codex, language: .english)
        let installedTwice = try String(contentsOf: agentsURL, encoding: .utf8)

        #expect(
            try installer.paneTeamPointerStatus(for: .codex, language: .english)
                == .installed
        )
        #expect(installedOnce == installedTwice)
        #expect(installedOnce.hasPrefix(existingBody))
        #expect(installedOnce.contains("<!-- mytty:pane-team:begin -->"))
        #expect(installedOnce.contains("<!-- mytty:pane-team:end -->"))
        #expect(installedOnce.contains("$MYTTY_CTL_BIN\" guide"))
        #expect(
            installedOnce.components(
                separatedBy: "<!-- mytty:pane-team:begin -->"
            ).count == 2
        )

        try installer.removePaneTeamPointer(.codex)
        let removed = try String(contentsOf: agentsURL, encoding: .utf8)

        #expect(
            try installer.paneTeamPointerStatus(for: .codex, language: .english)
                == .notInstalled
        )
        #expect(removed == existingBody)
    }

    @Test("creates AGENTS.md from scratch when Codex has none")
    func paneTeamPointerCodexCreatesFile() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let agentsURL = harness.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("AGENTS.md")
        let installer = harness.installer

        #expect(!FileManager.default.fileExists(atPath: agentsURL.path))
        try installer.installPaneTeamPointer(.codex, language: .english)

        #expect(
            try installer.paneTeamPointerStatus(for: .codex, language: .english)
                == .installed
        )
        let installed = try String(contentsOf: agentsURL, encoding: .utf8)
        #expect(installed.contains("<!-- mytty:pane-team:begin -->"))

        try installer.removePaneTeamPointer(.codex)
        let removed = try String(contentsOf: agentsURL, encoding: .utf8)

        #expect(
            try installer.paneTeamPointerStatus(for: .codex, language: .english)
                == .notInstalled
        )
        #expect(removed.isEmpty)
    }

    @Test("does not overwrite a Codex AGENTS.md that isn't valid text")
    func paneTeamPointerCodexMalformed() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let agentsURL = harness.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("AGENTS.md")
        try FileManager.default.createDirectory(
            at: agentsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let malformed = Data([0xFF, 0xFE, 0x00, 0xD8, 0x00])
        try malformed.write(to: agentsURL)

        #expect(throws: AgentIntegrationInstallerError.invalidConfiguration(
            agentsURL.path
        )) {
            try harness.installer.installPaneTeamPointer(
                .codex,
                language: .english
            )
        }
        #expect(try Data(contentsOf: agentsURL) == malformed)
    }

    @Test(
        "previews the exact pane-team pointer content without writing it",
        arguments: [PaneTeamPointerLanguage.english, .japanese]
    )
    func paneTeamPointerPreviewMatchesRealWrite(
        language: PaneTeamPointerLanguage
    ) throws {
        let harness = try Harness()
        defer { harness.remove() }
        let installer = harness.installer

        for provider: AgentProvider in [.claudeCode, .codex] {
            let url = try #require(installer.paneTeamPointerURL(for: provider))
            let preview = try #require(
                installer.paneTeamPointerPreview(
                    for: provider,
                    language: language
                )
            )

            // The preview must never touch disk: nothing should exist at
            // the pointer's URL (or, for Codex, its parent AGENTS.md) yet.
            #expect(!FileManager.default.fileExists(atPath: url.path))

            try installer.installPaneTeamPointer(provider, language: language)
            let written = try String(contentsOf: url, encoding: .utf8)

            switch provider {
            case .claudeCode:
                // Claude Code's pointer file is exactly the preview.
                #expect(written == preview)
            case .codex:
                // Codex's pointer is a block appended into AGENTS.md; the
                // preview is just that block's body.
                #expect(written.contains(preview))
            default:
                Issue.record("unexpected provider \(provider)")
            }
        }
    }

    @Test("returns nil pane-team pointer URL and preview for unsupported providers")
    func paneTeamPointerPreviewUnsupportedProviders() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let installer = harness.installer

        for provider: AgentProvider in [.openCode, .antigravity, .cursor] {
            #expect(installer.paneTeamPointerURL(for: provider) == nil)
            #expect(
                installer.paneTeamPointerPreview(
                    for: provider,
                    language: .english
                ) == nil
            )
        }
    }

    @Test("skips providers with no supported pane-team pointer location")
    func paneTeamPointerUnsupportedProviders() throws {
        let harness = try Harness()
        defer { harness.remove() }
        let installer = harness.installer

        for provider: AgentProvider in [.openCode, .antigravity, .cursor] {
            #expect(
                try installer.paneTeamPointerStatus(
                    for: provider,
                    language: .english
                ) == .notInstalled
            )
            try installer.installPaneTeamPointer(provider, language: .english)
            #expect(
                try installer.paneTeamPointerStatus(
                    for: provider,
                    language: .english
                ) == .notInstalled
            )
            try installer.removePaneTeamPointer(provider)
        }
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
