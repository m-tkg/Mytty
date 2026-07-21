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
        task: String
    ) -> String {
        let quotedTask = ShellQuoting.quote(task + workerContract)
        return command(provider: provider, access: access, quotedTask: quotedTask)
            + "\n"
    }

    private static func command(
        provider: AgentWorkerProvider,
        access: AgentAccessPolicy,
        quotedTask: String
    ) -> String {
        switch (provider, access) {
        case (.codex, .review):
            "command codex -s read-only -a never -- \(quotedTask)"
        case (.codex, .workspaceWrite):
            "command codex -s workspace-write -a never -- \(quotedTask)"
        case (.claude, .review):
            "command claude --permission-mode plan -- \(quotedTask)"
        case (.claude, .workspaceWrite):
            "command claude --permission-mode acceptEdits -- \(quotedTask)"
        case (.cursor, .review):
            "command cursor-agent --mode plan -- \(quotedTask)"
        case (.cursor, .workspaceWrite):
            "command cursor-agent --force --sandbox enabled -- \(quotedTask)"
        }
    }
}
