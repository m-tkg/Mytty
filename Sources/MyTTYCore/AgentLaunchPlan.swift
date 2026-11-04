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
        - Do not create hidden/native sub-agents. You are a worker controlled by another Mytty pane. (Opening a sibling pane via mytty-ctl split to give a TUI app under test a real pty is not a sub-agent -- that's fine.)
        - Do not ask the user routine implementation questions. Make a reasonable choice, record it, and continue.
        - When you start a distinct phase of the work (investigating, implementing, running tests, ...), report it with: mytty-ctl status "<a few words>"
        - End with a concise summary containing: findings or changed files, tests run and results, and remaining issues.
        """

    /// Typed ahead of the launch command so the spawn line (and everything
    /// the pane's shell runs after it) never persists into the user's
    /// shell history. macOS's `/etc/zshrc` sets `HISTFILE` unconditionally
    /// for every interactive zsh, so scrubbing the pane's environment
    /// cannot prevent the write — the unset has to happen inside the shell
    /// itself, on the very line being typed. Stock zsh flushes history to
    /// `HISTFILE` from memory when the shell exits, so unsetting it here
    /// suppresses persistence of the whole pane. `fc -p` then pushes the
    /// in-memory history list — which already contains this very line,
    /// plus everything loaded from `HISTFILE` at startup — onto zsh's
    /// history stack and switches to an empty list, so the injected line
    /// never shows up in arrow-key/Ctrl-R recall either; stock zsh has no
    /// `hist_ignore_space`, so the leading space alone doesn't keep it out
    /// of memory. The pushed list is never flushed (nothing pops it, and
    /// `HISTFILE` is already unset), while commands the user types later
    /// still get normal recall on the fresh list. The cost is that recall
    /// of pre-existing global history is gone in this pane. Setups with
    /// `inc_append_history`/`share_history` write each line as it is
    /// accepted — before any of this runs — which is what the leading
    /// space covers: such setups (oh-my-zsh and friends) also enable
    /// `hist_ignore_space`, which drops space-prefixed lines entirely.
    /// `builtin` dodges a shadowing user function; `2>/dev/null` silences
    /// shells without an `unset` builtin (fish) and shells whose `fc` has
    /// no `-p` (bash) — there the unset alone still blocks persistence.
    public static let historySuppressionPrefix
        = " builtin unset HISTFILE 2>/dev/null; builtin fc -p 2>/dev/null; "

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
        reasoningEffort: AgentReasoningEffort? = nil,
        inheritedModeArguments: [String]? = nil,
        workingDirectory: String? = nil,
        task: String
    ) -> String {
        let quotedTask = ShellQuoting.quote(task + workerContract)
        return historySuppressionPrefix + command(
            provider: provider,
            access: access,
            model: model,
            reasoningEffort: reasoningEffort,
            inheritedModeArguments: inheritedModeArguments,
            workingDirectory: workingDirectory,
            quotedTask: quotedTask
        ) + "\n"
    }

    /// The transient `initialInput` for `mytty-ctl new-tab/split --command`:
    /// a caller-supplied launch line delivered with the same one-shot,
    /// history-suppressed treatment `initialInput(provider:...)` gives an
    /// `agent spawn` launch command, so a hand-assembled launch-command-plus-
    /// task string (e.g. `claude --permission-mode acceptEdits -- "$(cat
    /// task.md)"`) reaches the new pane in one shell input instead of racing
    /// a separate `send` against the pane's still-initializing TUI.
    public static func initialInput(command: String) -> String {
        historySuppressionPrefix + command + "\n"
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
        case .claude, .cursor, .antigravity:
            return "--model \(quotedModel) "
        }
    }

    /// The provider's reasoning-effort flag with a trailing space, or the
    /// empty string when none was requested or the provider has no such
    /// flag (the control server rejects that combination before it gets
    /// here, so the empty fallback is only defensive). The value comes
    /// from a closed enum, so it needs no quoting.
    private static func reasoningEffortSegment(
        provider: AgentWorkerProvider,
        reasoningEffort: AgentReasoningEffort?
    ) -> String {
        guard let reasoningEffort,
              reasoningEffort.isSupported(by: provider)
        else { return "" }
        switch provider {
        case .codex:
            return "-c model_reasoning_effort=\(reasoningEffort.rawValue) "
        case .claude:
            return "--effort \(reasoningEffort.rawValue) "
        case .cursor:
            return ""
        case .antigravity:
            return "--effort \(reasoningEffort.rawValue) "
        }
    }

    /// Base for the writer's rules (`antigravityWriteAllowRules` extends these);
    /// the review worker has its own list below.
    /// agy matches `command(x)` as a whole-word command prefix and judges
    /// `;`, `&&`, pipes and `2>&1` per sub-command.
    private static let antigravityReadAllowRules = [
        "gh pr view", "gh pr diff", "gh pr list", "gh pr checks",
        "gh issue view", "gh api",
        "git status", "git blame",
        "cat", "ls", "grep", "head", "tail", "wc", "pwd",
        "mytty-ctl status",
    ]

    /// Allow rules for a review worker: broad, so that a review does not
    /// stop at a prompt nobody is told about. agy has no wildcard in rules,
    /// so a rule is always a command prefix and cannot fence off flags:
    /// `git diff|log|show --output=<path>` writes files, `rg --pre`,
    /// `find -exec`, `awk system()` and `python3` run arbitrary commands,
    /// and `gh api` can write to GitHub (`-X POST`). plan mode does not stop
    /// any of that (it only steers the model). `$(...)` and `<(...)` are
    /// never auto-approved: pipe instead (`git show x:f | nl -ba`).
    /// `rm`/`mv` are not listed because a rule cannot be scoped to /tmp.
    private static let antigravityReviewAllowRules: [String] =
        [
            "gh pr view", "gh pr diff", "gh pr list", "gh pr checks",
            "gh issue view", "gh issue list", "gh api",
            "git status", "git fetch", "git show", "git diff", "git log",
            "git blame", "git rev-parse", "git rev-list", "git grep",
            "git ls-files", "git ls-tree", "git cat-file", "git merge-base",
            "git show-ref", "git describe", "git diff-tree", "git shortlog",
            "git for-each-ref", "git name-rev",
            "python3", "mytty-ctl status",
            "cat", "nl", "head", "tail", "rg", "grep", "sed", "awk", "jq",
            "wc", "sort", "uniq", "diff", "ls", "find", "pwd",
        ].map { "command(\($0))" }
        // Redirects (`gh pr diff > /tmp/x.diff`) need a file-write grant.
        + ["write_file(/tmp)", "write_file(/private/tmp)"]

    /// Explicit denials for a review worker (deny beats allow in agy). A
    /// second layer, not a security boundary: matching is by prefix, so
    /// `git -C . push` or `gh api -X POST` are not caught.
    private static let antigravityReviewDenyRules = [
        "git push", "git commit", "git checkout", "git switch", "git reset",
        "git merge", "git rebase", "git clean", "git restore",
        "gh pr merge", "gh pr close", "gh pr edit", "gh repo", "gh release",
        "curl", "wget", "sudo", "rm", "rmdir", "mv",
    ].map { "command(\($0))" }

    /// Rules for a worker that edits and builds in its workspace. Scoped to
    /// subcommands so that push, merge, reset and deletions still stop at a
    /// prompt, as they do for claude's `acceptEdits`. `swift` and `make`
    /// are effectively arbitrary code execution; that is accepted.
    private static let antigravityWriteAllowRules = antigravityReadAllowRules
        .filter { $0 != "gh api" }
        + [
            "git add", "git commit", "git diff", "git log", "git show",
            "gh pr create", "gh pr comment", "gh issue list",
            "swift", "make", "mkdir", "touch",
        ]

    /// `--settings <json>` for `agy`: one shell-quoted argument holding
    /// session-only (never saved) settings. `trustedWorkspaces` pre-trusts
    /// the worker's directory so agy skips its first-run "Do you trust this
    /// folder" prompt; `permissions.allow` lists the shell commands allowed
    /// without asking. agy reports no approval events, so anything outside
    /// the rules stops the worker at an approval prompt nobody is told
    /// about. The JSON is built here and quoted as a whole, so a directory
    /// name with quotes, backslashes or shell metacharacters cannot add
    /// settings or break the command.
    private static func antigravitySettings(
        writable: Bool,
        workingDirectory: String?
    ) -> String {
        var permissions: [String: Any]
        if writable {
            permissions = ["allow": antigravityWriteAllowRules
                .map { "command(\($0))" }]
        } else {
            permissions = [
                "allow": antigravityReviewAllowRules,
                "deny": antigravityReviewDenyRules,
            ]
        }
        var settings: [String: Any] = ["permissions": permissions]
        if let workingDirectory {
            settings["trustedWorkspaces"] = [workingDirectory]
        }
        let data = (try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )) ?? Data("{}".utf8)
        return "--settings "
            + ShellQuoting.quote(String(decoding: data, as: UTF8.self))
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
        reasoningEffort: AgentReasoningEffort?,
        inheritedModeArguments: [String]?,
        workingDirectory: String?,
        quotedTask: String
    ) -> String {
        // Model and reasoning effort travel together as the leading
        // launch options, ahead of the access-derived mode flags.
        let modelFlag = modelSegment(provider: provider, model: model)
            + reasoningEffortSegment(
                provider: provider,
                reasoningEffort: reasoningEffort
            )
        if let inheritedModeArguments, !inheritedModeArguments.isEmpty {
            return inheritedCommand(
                provider: provider,
                modelFlag: modelFlag,
                inheritedModeArguments: inheritedModeArguments,
                workingDirectory: workingDirectory,
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
        case (.antigravity, .review):
            "command agy \(modelFlag)--mode plan "
                + "\(antigravitySettings(writable: false, workingDirectory: workingDirectory)) "
                + "-i \(quotedTask)"
        case (.antigravity, .workspaceWrite), (.antigravity, .inherit):
            "command agy \(modelFlag)--mode accept-edits "
                + "\(antigravitySettings(writable: true, workingDirectory: workingDirectory)) "
                + "-i \(quotedTask)"
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
        workingDirectory: String?,
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
        case .antigravity:
            // Only a lead in plan mode gets the review rules: plan mode does
            // not stop an allowed shell command (agy only keeps the model
            // from planning writes), so the allow and deny rules are what
            // limit a plan-mode lead's worker (see the review rule docs).
            let isPlan = zip(
                inheritedModeArguments,
                inheritedModeArguments.dropFirst()
            ).contains { $0 == "--mode" && $1 == "plan" }
            return "command agy \(modelFlag)\(quotedFlags) "
                + "\(antigravitySettings(writable: !isPlan, workingDirectory: workingDirectory)) "
                + "-i \(quotedTask)"
        }
    }
}
