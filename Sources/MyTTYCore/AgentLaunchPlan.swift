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

    /// The transient `initialInput` for a newly spawned worker pane: one
    /// fully quoted shell command ending in a trailing newline, so the pane
    /// launches the worker and hands it the task in a single keystroke
    /// burst instead of two racing `send`s.
    public static func initialInput(
        provider: AgentWorkerProvider,
        access: AgentAccessPolicy,
        model: String?,
        task: String
    ) -> String {
        let quotedTask = ShellQuoting.quote(task + workerContract)
        return command(
            provider: provider,
            access: access,
            model: model,
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

    private static func command(
        provider: AgentWorkerProvider,
        access: AgentAccessPolicy,
        model: String?,
        quotedTask: String
    ) -> String {
        let modelFlag = modelSegment(provider: provider, model: model)
        return switch (provider, access) {
        case (.codex, .review):
            "command codex \(modelFlag)-s read-only -a never -- \(quotedTask)"
        case (.codex, .workspaceWrite):
            "command codex \(modelFlag)-s workspace-write -a never -- \(quotedTask)"
        case (.claude, .review):
            "command claude \(modelFlag)--permission-mode plan -- \(quotedTask)"
        case (.claude, .workspaceWrite):
            "command claude \(modelFlag)--permission-mode acceptEdits -- \(quotedTask)"
        case (.cursor, .review):
            "command cursor-agent \(modelFlag)--mode plan -- \(quotedTask)"
        case (.cursor, .workspaceWrite):
            "command cursor-agent \(modelFlag)--force --sandbox enabled -- \(quotedTask)"
        }
    }
}
