import Foundation

/// Builds the one shell command `agent spawn` hands a new pane as transient
/// `initialInput`: the provider's launch flags for the requested access
/// policy, plus the task text (with the worker contract appended) as a
/// single quoted trailing argument. Launch command and task travel as one
/// shell input specifically so a worker never sees the task arrive as a
/// separate `send` after its TUI has already started drawing — see
/// `docs/explanation/mytty-ctl-architecture.md`.
public enum AgentLaunchPlan {
    /// Appended to every spawned task, after quoting is out of the
    /// question — the contract text becomes part of the quoted argument.
    /// Keep this in sync with `docs/how-to/orchestrate-agents-with-mytty-ctl.md`.
    public static let workerContract = """

        Mytty worker contract:
        - Work only in the current working directory unless the task explicitly says otherwise.
        - Continue until the assigned task is complete; run relevant tests when changes are made.
        - Do not create hidden/native sub-agents. You are a worker controlled by another Mytty pane.
        - Do not ask the user routine implementation questions. Make a reasonable choice, record it, and continue.
        - End with a concise summary containing: findings or changed files, tests run and results, and remaining issues.
        """

    /// Typed ahead of the launch command so the spawn line (and everything
    /// the pane's shell runs after it) never persists into the user's
    /// shell history. macOS's `/etc/zshrc` sets `HISTFILE` unconditionally
    /// for every interactive zsh, so scrubbing the pane's environment
    /// cannot prevent the write — the unset has to happen inside the shell
    /// itself, on the very line being typed. Stock zsh flushes history to
    /// `HISTFILE` from memory when the shell exits, so unsetting it here
    /// suppresses persistence of the whole pane while leaving in-memory
    /// history (arrow-key recall) intact. Setups with
    /// `inc_append_history`/`share_history` write each line as it is
    /// accepted — before the unset runs — which is what the leading space
    /// covers: such setups (oh-my-zsh and friends) also enable
    /// `hist_ignore_space`, which drops space-prefixed lines entirely.
    /// `builtin` dodges a shadowing user function; `2>/dev/null` silences
    /// shells without an `unset` builtin (fish).
    public static let historySuppressionPrefix
        = " builtin unset HISTFILE 2>/dev/null; "

    /// The transient `initialInput` for a newly spawned worker pane: one
    /// fully quoted shell command ending in a trailing newline, so the pane
    /// launches the worker and hands it the task in a single keystroke
    /// burst instead of two racing `send`s. The command is prefixed with
    /// `historySuppressionPrefix` so it stays out of the shell's persisted
    /// history.
    public static func initialInput(
        provider: AgentWorkerProvider,
        access: AgentAccessPolicy,
        model: String?,
        inheritedModeArguments: [String]? = nil,
        task: String
    ) -> String {
        let quotedTask = ShellQuoting.quote(task + workerContract)
        return historySuppressionPrefix + command(
            provider: provider,
            access: access,
            model: model,
            inheritedModeArguments: inheritedModeArguments,
            quotedTask: quotedTask
        ) + "\n"
    }

    /// `--model <quoted-model> ` (with a trailing space) for the given
    /// provider, or the empty string when no model was requested — kept
    /// separate from `command(...)` so each provider's flag ordering below
    /// stays a single readable line.
    private static func modelSegment(
        provider: AgentWorkerProvider,
        model: String?
    ) -> String {
        guard let model else { return "" }
        let quotedModel = ShellQuoting.quote(model)
        switch provider {
        case .codex:
            return "-m \(quotedModel) "
        case .claude, .cursor:
            return "--model \(quotedModel) "
        }
    }

    /// The codex flags that already govern approval behavior on their own
    /// -- when one of these came from the lead's own argv, appending our
    /// usual `-a never` on top would be redundant at best and could
    /// override an inherited `-a`/`--ask-for-approval` value at worst.
    private static let codexApprovalGoverningFlags: Set<String> = [
        "-a", "--ask-for-approval", "--full-auto", "--yolo",
        "--dangerously-bypass-approvals-and-sandbox",
    ]

    private static func command(
        provider: AgentWorkerProvider,
        access: AgentAccessPolicy,
        model: String?,
        inheritedModeArguments: [String]?,
        quotedTask: String
    ) -> String {
        let modelFlag = modelSegment(provider: provider, model: model)
        if let inheritedModeArguments, !inheritedModeArguments.isEmpty {
            return inheritedCommand(
                provider: provider,
                modelFlag: modelFlag,
                inheritedModeArguments: inheritedModeArguments,
                quotedTask: quotedTask
            )
        }
        // `.inherit` reaching here with nothing to inherit means either the
        // lead is running in its default mode or (defensively) that a
        // caller passed `.inherit` without resolving it first -- either
        // way, workspace-write is the right fallback, so `.inherit` is
        // folded into the `.workspaceWrite` cases below rather than given
        // its own arm.
        return switch (provider, access) {
        case (.codex, .review):
            "command codex \(modelFlag)-s read-only -a never -- \(quotedTask)"
        case (.codex, .workspaceWrite), (.codex, .inherit):
            "command codex \(modelFlag)-s workspace-write -a never -- \(quotedTask)"
        case (.claude, .review):
            "command claude \(modelFlag)--permission-mode plan -- \(quotedTask)"
        case (.claude, .workspaceWrite), (.claude, .inherit):
            "command claude \(modelFlag)--permission-mode acceptEdits -- \(quotedTask)"
        case (.cursor, .review):
            "command cursor-agent \(modelFlag)--mode plan -- \(quotedTask)"
        case (.cursor, .workspaceWrite), (.cursor, .inherit):
            "command cursor-agent \(modelFlag)--force --sandbox enabled -- \(quotedTask)"
        }
    }

    /// Builds the launch command for `--access inherit` once the lead's
    /// mode flags have already been extracted and validated by
    /// `AgentModeInheritance` -- each token is shell-quoted individually
    /// (not the joined string) so a value containing shell metacharacters
    /// can't reshape the command.
    private static func inheritedCommand(
        provider: AgentWorkerProvider,
        modelFlag: String,
        inheritedModeArguments: [String],
        quotedTask: String
    ) -> String {
        let quotedFlags = inheritedModeArguments
            .map { ShellQuoting.quote($0) }
            .joined(separator: " ")
        switch provider {
        case .claude:
            return "command claude \(modelFlag)\(quotedFlags) -- \(quotedTask)"
        case .codex:
            let hasApprovalFlag = inheritedModeArguments.contains {
                codexApprovalGoverningFlags.contains($0)
            }
            let approvalSuffix = hasApprovalFlag ? "" : " -a never"
            return "command codex \(modelFlag)\(quotedFlags)\(approvalSuffix)"
                + " -- \(quotedTask)"
        case .cursor:
            return "command cursor-agent \(modelFlag)\(quotedFlags) -- \(quotedTask)"
        }
    }
}
