import Foundation

/// The model string the user selected for a Claude Code session, as opposed
/// to the canonical model ID a transcript records.
///
/// The distinction matters for the context window: Claude Code enables the
/// 1M window from the *selection* (`opus[1m]`, `--model sonnet[1m]`), while
/// `message.model` in the transcript is always the normalized ID
/// (`claude-opus-5`) with no `[1m]` suffix. Reading the percentage off the
/// transcript alone therefore treats every 1M session as a 200k one.
///
/// Only the sources Claude Code itself consults are read, in its precedence
/// order. The `ANTHROPIC_MODEL` and `CLAUDE_CODE_MAX_CONTEXT_TOKENS`
/// environment variables are deliberately not consulted — they would require
/// reading another process's environment.
public enum ClaudeCodeModelSelection {
    public static func resolve(
        arguments: [String],
        workingDirectory: URL?,
        claudeHome: URL = ClaudeCodeSessionInspector.defaultClaudeHome
    ) -> String? {
        if let fromArguments = model(fromArguments: arguments) {
            return fromArguments
        }
        for settings in settingsURLs(
            workingDirectory: workingDirectory,
            claudeHome: claudeHome
        ) {
            if let model = model(fromSettings: settings) {
                return model
            }
        }
        return nil
    }

    /// `--model <value>` and `--model=<value>`; the last occurrence wins,
    /// matching how the CLI parses repeated flags.
    static func model(fromArguments arguments: [String]) -> String? {
        var model: String?
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            if argument == "--model" {
                let next = arguments.index(after: index)
                if next < arguments.endIndex {
                    model = AgentSessionValidation.label(arguments[next])
                        ?? model
                    index = next
                }
            } else if argument.hasPrefix("--model=") {
                model = AgentSessionValidation.label(
                    String(argument.dropFirst("--model=".count))
                ) ?? model
            }
            index = arguments.index(after: index)
        }

        return model
    }

    /// Highest precedence first. Project settings live next to the working
    /// directory, so a session started elsewhere simply misses them and
    /// falls through to the user-level file.
    private static func settingsURLs(
        workingDirectory: URL?,
        claudeHome: URL
    ) -> [URL] {
        var urls: [URL] = []
        if let workingDirectory {
            let project = workingDirectory
                .appendingPathComponent(".claude", isDirectory: true)
            urls.append(
                project.appendingPathComponent("settings.local.json")
            )
            urls.append(project.appendingPathComponent("settings.json"))
        }
        urls.append(claudeHome.appendingPathComponent("settings.json"))
        return urls
    }

    /// Settings files are user-editable and may be malformed or carry a
    /// `model` of any type, so every failure mode falls through to the next
    /// source rather than surfacing.
    private static func model(fromSettings url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return nil }
        return AgentSessionValidation.label(object["model"] as? String)
    }
}
