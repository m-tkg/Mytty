import Foundation

/// Extracts a lead agent process's mode-relevant launch flags so `agent
/// spawn --access inherit` can splice them onto a worker of the same
/// provider instead of using the fixed review/workspace-write flag sets in
/// `AgentLaunchPlan`. Pure and Foundation-only so it's unit-testable
/// without touching `sysctl`/`KERN_PROCARGS2` — the caller
/// (`AgentJobCoordinator`) is responsible for reading the lead's argv via
/// `TerminalAgentProcessDetector.invocation(processID:)` and handing it
/// here.
///
/// This reads argv only, which is a snapshot of how the lead was
/// *launched* — a mode switched interactively at runtime (e.g. Claude
/// Code's shift+tab permission-mode cycling) never touches argv and is
/// therefore invisible here. Argv is the best signal available short of
/// scraping the provider's own UI state, which the rest of Mytty's agent
/// integration deliberately never does (see "Agent integration model" in
/// `CLAUDE.md`).
public enum AgentModeInheritance {
    private struct FlagSpec {
        let names: [String]
        let takesValue: Bool
    }

    private static let claudeFlags: [FlagSpec] = [
        FlagSpec(names: ["--permission-mode"], takesValue: true),
        FlagSpec(names: ["--dangerously-skip-permissions"], takesValue: false),
    ]

    private static let codexFlags: [FlagSpec] = [
        FlagSpec(names: ["-s", "--sandbox"], takesValue: true),
        FlagSpec(names: ["-a", "--ask-for-approval"], takesValue: true),
        FlagSpec(names: ["--full-auto"], takesValue: false),
        FlagSpec(names: ["--yolo"], takesValue: false),
        FlagSpec(
            names: ["--dangerously-bypass-approvals-and-sandbox"],
            takesValue: false
        ),
    ]

    private static let cursorFlags: [FlagSpec] = [
        FlagSpec(names: ["--mode"], takesValue: true),
        FlagSpec(names: ["--force"], takesValue: false),
        FlagSpec(names: ["--sandbox"], takesValue: true),
    ]

    private static func flags(for provider: AgentWorkerProvider) -> [FlagSpec] {
        switch provider {
        case .claude: claudeFlags
        case .codex: codexFlags
        case .cursor: cursorFlags
        }
    }

    /// Scans `leadArguments` (the lead process's argv, KERN_PROCARGS2
    /// order — argv[0] is harmless to include since it's an executable
    /// path/name and can never match a flag spelling) for the flags this
    /// provider treats as mode-relevant, preserving the order they appear
    /// in. Both `--flag value` and `--flag=value` spellings are
    /// recognized. Returns `[]` when nothing mode-relevant was found,
    /// which the caller treats as "the lead runs in its default mode" and
    /// falls back to the normal access-derived flags.
    public static func inheritedModeArguments(
        provider: AgentWorkerProvider,
        leadArguments: [String]
    ) -> [String] {
        let specs = flags(for: provider)
        var result: [String] = []
        var index = 0
        while index < leadArguments.count {
            let token = leadArguments[index]
            guard let match = matchingFlag(token, in: specs) else {
                index += 1
                continue
            }
            let (name, spec, inlineValue) = match

            guard spec.takesValue else {
                result.append(name)
                index += 1
                continue
            }

            if let inlineValue {
                // "--flag=value" spelling: the whole token was consumed,
                // regardless of whether the value validates.
                if isValidValue(inlineValue) {
                    result.append(name)
                    result.append(inlineValue)
                }
                index += 1
                continue
            }

            // "--flag value" spelling: the value is the next token, if
            // any. A missing or malformed value (empty, too long, control
            // characters, whitespace, or itself starting with "-" as if
            // it were another flag) means the lead's argv didn't actually
            // supply a usable value here -- drop the flag entirely rather
            // than emit it dangling, and leave the next token untouched so
            // it still gets evaluated as its own argument.
            let valueIndex = index + 1
            guard valueIndex < leadArguments.count,
                  isValidValue(leadArguments[valueIndex])
            else {
                index += 1
                continue
            }
            result.append(name)
            result.append(leadArguments[valueIndex])
            index += 2
        }
        return result
    }

    /// Finds the spec (and matched spelling) for `token` among `specs`,
    /// splitting out an inline `=value` when the token uses that spelling
    /// for a flag that takes a value.
    private static func matchingFlag(
        _ token: String,
        in specs: [FlagSpec]
    ) -> (name: String, spec: FlagSpec, inlineValue: String?)? {
        for spec in specs {
            for name in spec.names {
                if token == name {
                    return (name, spec, nil)
                }
                if spec.takesValue, token.hasPrefix(name + "=") {
                    return (name, spec, String(token.dropFirst(name.count + 1)))
                }
            }
        }
        return nil
    }

    /// A flag value copied from another process's argv is externally
    /// sourced input, same as any provider transcript field elsewhere in
    /// this module -- validate before it can become part of a shell
    /// command: nonempty, bounded length, no control characters, no
    /// whitespace (a value can never legitimately contain a space; argv
    /// already split on spaces), and must not start with "-" (that shape
    /// means the flag was given without a value and the next token is
    /// itself another flag).
    private static func isValidValue(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.unicodeScalars.count <= 100,
              !value.hasPrefix("-"),
              !value.contains(where: { $0.isWhitespace }),
              value.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              })
        else { return false }
        return true
    }
}
