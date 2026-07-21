import Foundation

public enum AgentIntegrationStatus: Equatable, Sendable {
    case notInstalled
    case installed
    case needsRepair
}

public enum AgentIntegrationInstallerError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case missingHookExecutable(String)
}

public struct AgentIntegrationInstaller {
    private typealias JSONObject = [String: Any]

    private static let codexEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "PermissionRequest",
        "PostToolUse",
        "Stop",
    ]
    private static let claudeCodeEvents = [
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "PermissionRequest",
        "PostToolBatch",
        "Notification",
        "Stop",
        "StopFailure",
    ]
    private static let cursorEvents = [
        "beforeSubmitPrompt",
        "postToolUse",
        "postToolUseFailure",
        "beforeShellExecution",
        "afterShellExecution",
        "stop",
    ]

    private let homeDirectory: URL
    private let sourceHookExecutable: URL
    private let fileManager: FileManager

    public let installedHookExecutable: URL

    public init(
        homeDirectory: URL,
        applicationSupportDirectory: URL,
        sourceHookExecutable: URL,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.sourceHookExecutable = sourceHookExecutable
        self.fileManager = fileManager
        installedHookExecutable = applicationSupportDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("mytty-agent-hook", isDirectory: false)
    }

    public func status(
        for provider: AgentProvider
    ) throws -> AgentIntegrationStatus {
        switch provider {
        case .codex, .claudeCode:
            guard let configuration = try readConfiguration(
                at: configurationURL(for: provider)
            ) else { return .notInstalled }
            let hasOwnedHandler = containsOwnedHandler(
                in: configuration,
                provider: provider
            )
            guard hasOwnedHandler else { return .notInstalled }
            guard installedHookExecutableIsCurrent() else {
                return .needsRepair
            }
            let expected = try configurationByInstalling(
                provider,
                into: configuration,
                sourceURL: configurationURL(for: provider)
            )
            return dictionariesEqual(configuration, expected)
                ? .installed
                : .needsRepair

        case .openCode:
            let url = configurationURL(for: provider)
            guard fileManager.fileExists(atPath: url.path) else {
                return .notInstalled
            }
            guard installedHookExecutableIsCurrent() else {
                return .needsRepair
            }
            let current = try Data(contentsOf: url)
            return current == openCodePluginData()
                ? .installed
                : .needsRepair

        case .antigravity:
            let directory = antigravityPluginDirectory
            guard fileManager.fileExists(atPath: directory.path) else {
                return .notInstalled
            }
            guard installedHookExecutableIsCurrent() else {
                return .needsRepair
            }
            let manifest = directory.appendingPathComponent("plugin.json")
            let hooks = directory.appendingPathComponent("hooks.json")
            guard let currentManifest = try? Data(contentsOf: manifest),
                  let currentHooks = try? Data(contentsOf: hooks)
            else { return .needsRepair }
            return currentManifest == antigravityManifestData()
                    && currentHooks == antigravityHooksData()
                ? .installed
                : .needsRepair

        case .cursor:
            let url = configurationURL(for: provider)
            guard let configuration = try readConfiguration(at: url) else {
                return .notInstalled
            }
            guard containsOwnedCursorHandler(in: configuration) else {
                return .notInstalled
            }
            guard installedHookExecutableIsCurrent() else {
                return .needsRepair
            }
            let expected = try configurationByInstallingCursor(
                into: configuration,
                sourceURL: url
            )
            return dictionariesEqual(configuration, expected)
                ? .installed
                : .needsRepair
        }
    }

    public func install(_ provider: AgentProvider) throws {
        if provider == .antigravity {
            try installHookExecutable()
            try writeAtomically(
                antigravityManifestData(),
                to: antigravityPluginDirectory
                    .appendingPathComponent("plugin.json"),
                defaultMode: 0o600
            )
            try writeAtomically(
                antigravityHooksData(),
                to: antigravityPluginDirectory
                    .appendingPathComponent("hooks.json"),
                defaultMode: 0o600
            )
            return
        }

        let targetURL = configurationURL(for: provider)
        let targetData: Data
        switch provider {
        case .codex, .claudeCode:
            let configuration = try readConfiguration(at: targetURL) ?? [:]
            let updated = try configurationByInstalling(
                provider,
                into: configuration,
                sourceURL: targetURL
            )
            targetData = try encodedConfiguration(updated)
        case .openCode:
            targetData = openCodePluginData()
        case .cursor:
            let configuration = try readConfiguration(at: targetURL) ?? [
                "version": 1,
            ]
            targetData = try encodedConfiguration(
                configurationByInstallingCursor(
                    into: configuration,
                    sourceURL: targetURL
                )
            )
        case .antigravity:
            preconditionFailure("Antigravity is handled before this switch")
        }

        try installHookExecutable()
        try writeAtomically(targetData, to: targetURL, defaultMode: 0o600)
    }

    public func remove(_ provider: AgentProvider) throws {
        if provider == .antigravity {
            guard fileManager.fileExists(
                atPath: antigravityPluginDirectory.path
            ) else { return }
            try fileManager.removeItem(at: antigravityPluginDirectory)
            return
        }

        let url = configurationURL(for: provider)
        switch provider {
        case .codex, .claudeCode:
            guard let configuration = try readConfiguration(at: url) else {
                return
            }
            let updated = try configurationByRemovingOwnedHandlers(
                provider,
                from: configuration,
                sourceURL: url
            )
            guard !dictionariesEqual(configuration, updated) else { return }
            try writeAtomically(
                try encodedConfiguration(updated),
                to: url,
                defaultMode: 0o600
            )
        case .openCode:
            guard fileManager.fileExists(atPath: url.path) else { return }
            try fileManager.removeItem(at: url)
        case .cursor:
            guard let configuration = try readConfiguration(at: url) else {
                return
            }
            let updated = try configurationByRemovingCursorHandlers(
                from: configuration,
                sourceURL: url
            )
            guard !dictionariesEqual(configuration, updated) else { return }
            try writeAtomically(
                try encodedConfiguration(updated),
                to: url,
                defaultMode: 0o600
            )
        case .antigravity:
            preconditionFailure("Antigravity is handled before this switch")
        }
    }

    private func configurationURL(for provider: AgentProvider) -> URL {
        switch provider {
        case .codex:
            homeDirectory
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("hooks.json", isDirectory: false)
        case .claudeCode:
            homeDirectory
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json", isDirectory: false)
        case .openCode:
            homeDirectory
                .appendingPathComponent(
                    ".config/opencode/plugins",
                    isDirectory: true
                )
                .appendingPathComponent("mytty.js", isDirectory: false)
        case .antigravity:
            antigravityPluginDirectory.appendingPathComponent("hooks.json")
        case .cursor:
            homeDirectory
                .appendingPathComponent(".cursor", isDirectory: true)
                .appendingPathComponent("hooks.json", isDirectory: false)
        }
    }

    private var antigravityPluginDirectory: URL {
        homeDirectory
            .appendingPathComponent(".gemini/config/plugins", isDirectory: true)
            .appendingPathComponent("mytty", isDirectory: true)
    }

    private func readConfiguration(at url: URL) throws -> JSONObject? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let object = try JSONSerialization.jsonObject(
                with: Data(contentsOf: url)
            )
            guard let configuration = object as? JSONObject else {
                throw AgentIntegrationInstallerError.invalidConfiguration(
                    url.path
                )
            }
            return configuration
        } catch is AgentIntegrationInstallerError {
            throw AgentIntegrationInstallerError.invalidConfiguration(url.path)
        } catch {
            throw AgentIntegrationInstallerError.invalidConfiguration(url.path)
        }
    }

    private func configurationByInstalling(
        _ provider: AgentProvider,
        into configuration: JSONObject,
        sourceURL: URL
    ) throws -> JSONObject {
        var updated = try configurationByRemovingOwnedHandlers(
            provider,
            from: configuration,
            sourceURL: sourceURL
        )
        var hooks = try hooksObject(in: updated, sourceURL: sourceURL)
        for event in expectedEvents(for: provider) {
            var groups = try eventGroups(
                event,
                in: hooks,
                sourceURL: sourceURL
            )
            groups.append(expectedGroup(for: provider, event: event))
            hooks[event] = groups
        }
        updated["hooks"] = hooks
        return updated
    }

    private func configurationByRemovingOwnedHandlers(
        _ provider: AgentProvider,
        from configuration: JSONObject,
        sourceURL: URL
    ) throws -> JSONObject {
        var updated = configuration
        var hooks = try hooksObject(in: configuration, sourceURL: sourceURL)
        for event in Array(hooks.keys) {
            let groups = try eventGroups(
                event,
                in: hooks,
                sourceURL: sourceURL
            )
            let filtered = groups.compactMap { group -> JSONObject? in
                guard let handlers = group["hooks"] as? [JSONObject] else {
                    return group
                }
                let remaining = handlers.filter {
                    !isOwnedHandler($0, provider: provider)
                }
                guard remaining.count != handlers.count else { return group }
                guard !remaining.isEmpty else { return nil }
                var preserved = group
                preserved["hooks"] = remaining
                return preserved
            }
            if filtered.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = filtered
            }
        }
        if hooks.isEmpty {
            updated.removeValue(forKey: "hooks")
        } else {
            updated["hooks"] = hooks
        }
        return updated
    }

    private func configurationByInstallingCursor(
        into configuration: JSONObject,
        sourceURL: URL
    ) throws -> JSONObject {
        var updated = try configurationByRemovingCursorHandlers(
            from: configuration,
            sourceURL: sourceURL
        )
        var hooks = try cursorHooksObject(
            in: updated,
            sourceURL: sourceURL
        )
        for event in Self.cursorEvents {
            var handlers = try cursorHandlers(
                event,
                in: hooks,
                sourceURL: sourceURL
            )
            handlers.append([
                "type": "command",
                "command": codexCommand(provider: .cursor),
            ])
            hooks[event] = handlers
        }
        updated["hooks"] = hooks
        if updated["version"] == nil {
            updated["version"] = 1
        }
        return updated
    }

    private func configurationByRemovingCursorHandlers(
        from configuration: JSONObject,
        sourceURL: URL
    ) throws -> JSONObject {
        var updated = configuration
        var hooks = try cursorHooksObject(
            in: configuration,
            sourceURL: sourceURL
        )
        for event in Array(hooks.keys) {
            let handlers = try cursorHandlers(
                event,
                in: hooks,
                sourceURL: sourceURL
            )
            let remaining = handlers.filter { !isOwnedCursorHandler($0) }
            if remaining.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = remaining
            }
        }
        if hooks.isEmpty {
            updated.removeValue(forKey: "hooks")
        } else {
            updated["hooks"] = hooks
        }
        return updated
    }

    private func cursorHooksObject(
        in configuration: JSONObject,
        sourceURL: URL
    ) throws -> JSONObject {
        guard let value = configuration["hooks"] else { return [:] }
        guard let hooks = value as? JSONObject else {
            throw AgentIntegrationInstallerError.invalidConfiguration(
                sourceURL.path
            )
        }
        return hooks
    }

    private func cursorHandlers(
        _ event: String,
        in hooks: JSONObject,
        sourceURL: URL
    ) throws -> [JSONObject] {
        guard let value = hooks[event] else { return [] }
        guard let handlers = value as? [JSONObject] else {
            throw AgentIntegrationInstallerError.invalidConfiguration(
                sourceURL.path
            )
        }
        return handlers
    }

    private func containsOwnedCursorHandler(
        in configuration: JSONObject
    ) -> Bool {
        guard let hooks = configuration["hooks"] as? JSONObject else {
            return false
        }
        return hooks.values.contains { value in
            guard let handlers = value as? [JSONObject] else { return false }
            return handlers.contains(where: isOwnedCursorHandler)
        }
    }

    private func isOwnedCursorHandler(_ handler: JSONObject) -> Bool {
        handler["command"] as? String == codexCommand(provider: .cursor)
    }

    private func hooksObject(
        in configuration: JSONObject,
        sourceURL: URL
    ) throws -> JSONObject {
        guard let value = configuration["hooks"] else { return [:] }
        guard let hooks = value as? JSONObject else {
            throw AgentIntegrationInstallerError.invalidConfiguration(
                sourceURL.path
            )
        }
        return hooks
    }

    private func eventGroups(
        _ event: String,
        in hooks: JSONObject,
        sourceURL: URL
    ) throws -> [JSONObject] {
        guard let value = hooks[event] else { return [] }
        guard let groups = value as? [JSONObject] else {
            throw AgentIntegrationInstallerError.invalidConfiguration(
                sourceURL.path
            )
        }
        return groups
    }

    private func containsOwnedHandler(
        in configuration: JSONObject,
        provider: AgentProvider
    ) -> Bool {
        guard let hooks = configuration["hooks"] as? JSONObject else {
            return false
        }
        return hooks.values.contains { value in
            guard let groups = value as? [JSONObject] else { return false }
            return groups.contains { group in
                guard let handlers = group["hooks"] as? [JSONObject] else {
                    return false
                }
                return handlers.contains {
                    isOwnedHandler($0, provider: provider)
                }
            }
        }
    }

    private func isOwnedHandler(
        _ handler: JSONObject,
        provider: AgentProvider
    ) -> Bool {
        guard handler["type"] as? String == "command" else { return false }
        switch provider {
        case .codex:
            return handler["command"] as? String
                == codexCommand(provider: provider)
        case .claudeCode:
            return handler["command"] as? String
                    == installedHookExecutable.path
                && handler["args"] as? [String] == [provider.rawValue]
        case .openCode:
            return false
        case .antigravity, .cursor:
            return false
        }
    }

    private func expectedEvents(for provider: AgentProvider) -> [String] {
        switch provider {
        case .codex:
            Self.codexEvents
        case .claudeCode:
            Self.claudeCodeEvents
        case .openCode:
            []
        case .antigravity, .cursor:
            []
        }
    }

    private func expectedGroup(
        for provider: AgentProvider,
        event: String
    ) -> JSONObject {
        var group: JSONObject = [
            "hooks": [expectedHandler(for: provider)],
        ]
        if provider == .claudeCode, event == "Notification" {
            group["matcher"] = [
                "permission_prompt",
                "idle_prompt",
                "agent_needs_input",
                "elicitation_dialog",
            ].joined(separator: "|")
        }
        return group
    }

    private func expectedHandler(for provider: AgentProvider) -> JSONObject {
        switch provider {
        case .codex:
            [
                "type": "command",
                "command": codexCommand(provider: provider),
                "timeout": 5,
            ]
        case .claudeCode:
            [
                "type": "command",
                "command": installedHookExecutable.path,
                "args": [provider.rawValue],
                "timeout": 5,
            ]
        case .openCode:
            [:]
        case .antigravity, .cursor:
            [:]
        }
    }

    private func codexCommand(provider: AgentProvider) -> String {
        "\(shellQuote(installedHookExecutable.path)) \(provider.rawValue)"
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func installHookExecutable() throws {
        guard fileManager.isExecutableFile(atPath: sourceHookExecutable.path)
        else {
            throw AgentIntegrationInstallerError.missingHookExecutable(
                sourceHookExecutable.path
            )
        }
        if sourceHookExecutable.standardizedFileURL
            == installedHookExecutable.standardizedFileURL {
            return
        }
        try writeAtomically(
            Data(contentsOf: sourceHookExecutable),
            to: installedHookExecutable,
            defaultMode: 0o755,
            forcedMode: 0o755
        )
    }

    private func installedHookExecutableIsCurrent() -> Bool {
        guard fileManager.isExecutableFile(
            atPath: installedHookExecutable.path
        ), fileManager.isExecutableFile(atPath: sourceHookExecutable.path)
        else { return false }
        if sourceHookExecutable.standardizedFileURL
            == installedHookExecutable.standardizedFileURL {
            return true
        }
        guard let source = try? Data(contentsOf: sourceHookExecutable),
              let installed = try? Data(contentsOf: installedHookExecutable)
        else { return false }
        return source == installed
    }

    private func encodedConfiguration(
        _ configuration: JSONObject
    ) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: configuration,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }

    private func writeAtomically(
        _ data: Data,
        to url: URL,
        defaultMode: Int,
        forcedMode: Int? = nil
    ) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let destination = url.resolvingSymlinksInPath()
        let existingMode = try? fileManager.attributesOfItem(
            atPath: destination.path
        )[.posixPermissions] as? Int
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: forcedMode ?? existingMode ?? defaultMode],
            ofItemAtPath: destination.path
        )
    }

    private func dictionariesEqual(
        _ lhs: JSONObject,
        _ rhs: JSONObject
    ) -> Bool {
        lhs as NSDictionary == rhs as NSDictionary
    }

    private func openCodePluginData() -> Data {
        let executable = javaScriptLiteral(installedHookExecutable.path)
        return Data(
            """
            // Generated by mytty. Changes to this file are replaced on repair.
            const hookExecutable = \(executable)
            const relevantEvents = new Set([
              "message.updated",
              "permission.asked",
              "permission.updated",
              "permission.replied",
              "question.asked",
              "session.idle",
              "session.error",
            ])

            export const MyTTYAttentionPlugin = async () => {
              const runBySession = new Map()

              return {
                event: async ({ event }) => {
                  const properties = event.properties ?? {}
                  const info = properties.info ?? {}
                  const sessionID = properties.sessionID ?? info.sessionID

                  if (
                    event.type === "message.updated" &&
                    info.role === "user" &&
                    sessionID &&
                    info.id
                  ) {
                    runBySession.set(sessionID, info.id)
                  }

                  if (!relevantEvents.has(event.type) || !sessionID) return
                  const runID = runBySession.get(sessionID)
                  if (!runID) return

                  const child = Bun.spawn([hookExecutable, "opencode"], {
                    stdin: "pipe",
                    stdout: "ignore",
                    stderr: "ignore",
                    env: process.env,
                  })
                  child.stdin.write(JSON.stringify({ run_id: runID, event }))
                  child.stdin.end()
                  await child.exited

                  if (
                    event.type === "session.idle" ||
                    event.type === "session.error"
                  ) {
                    runBySession.delete(sessionID)
                  }
                },
              }
            }
            """.utf8
        )
    }

    private func antigravityManifestData() -> Data {
        ownedJSONData([
            "$schema": "https://antigravity.google/schemas/v1/plugin.json",
            "name": "mytty",
            "version": "1.0.0",
            "description": "Routes Antigravity lifecycle events to mytty Attention.",
        ])
    }

    private func antigravityHooksData() -> Data {
        let handler: JSONObject = [
            "type": "command",
            "command": codexCommand(provider: .antigravity),
            "timeout": 5,
        ]
        return ownedJSONData([
            "mytty-attention": [
                "PreInvocation": [handler],
                "PostInvocation": [handler],
                "Stop": [handler],
            ],
        ])
    }

    private func ownedJSONData(_ object: JSONObject) -> Data {
        guard let data = try? encodedConfiguration(object) else {
            preconditionFailure("Owned JSON configuration is not encodable")
        }
        return data
    }

    private func javaScriptLiteral(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try? encoder.encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}
