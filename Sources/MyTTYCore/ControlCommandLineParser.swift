import Foundation

/// Pure argument parsing for the `mytty-ctl` CLI, kept separate from
/// `MyTTYCtl/main.swift` (which only does socket I/O) so it can be unit
/// tested without spawning a process — the same reasoning that keeps
/// protocol/reducer logic in `MyTTYCore` rather than in `MyTTYApp`.
public enum ControlCommandLineError: Error, Equatable, Sendable {
    case invalidArguments(String)
}

public enum ControlCommandLineParser {
    public static let usage = """
    mytty-ctl <command> [arguments]

    Commands:
      agent spawn --provider <codex|claude|cursor> (--task <text> | --task-file <path>)
                  [--anchor <pane-id>] [--direction <left|right|up|down>]
                  [--cwd <path>] [--access <review|workspace-write>] [--label <text>]
      agent wait <job-id> --until <running|attention|completed> [--timeout-seconds <n>]
      agent result <job-id>
      agent send <job-id> <text> [--enter]
      agent focus <job-id>
      agent close <job-id>

      list
      new-tab [--cwd <path>]
      split <pane-id> <left|right|up|down> [--cwd <path>]
      send <pane-id> <text> [--enter]
      send-key <pane-id> <key> [--modifiers <mod,mod,...>]
      read <pane-id>
      wait <pane-id> --until <idle|attention> [--timeout-seconds <n>]
      close-pane <pane-id>
      focus <pane-id>

    Every command prints one JSON object to stdout on success and exits 0.
    On failure it prints a message to stderr and exits 1. Run
    `mytty-ctl guide` for the pane-team recipes this is meant to support,
    or see https://github.com/m-tkg/mytty for the full documentation.
    """

    /// The pane-team operating manual: environment variables, the
    /// split/send/wait/read flow, and per-provider launch flags. Written
    /// for an AI agent to read via `mytty-ctl guide`, not routed through
    /// `MyTTYLocalization` since it's never shown as app UI. This is the
    /// single source of truth for the recipe — docs reference it rather
    /// than duplicating it, so it can't drift out of sync with a shipped
    /// binary.
    public static let paneTeamGuide = """
    Mytty pane-team guide

    This is the operating manual for running other AI agents as sub-agents in
    Mytty panes via mytty-ctl. It is written for an AI agent to read, not a
    human GUI user.

    ENVIRONMENT

    Every pane Mytty opens sets these automatically; no setup is needed before
    calling mytty-ctl from inside a pane:

      MYTTY_CTL_BIN        absolute path to the mytty-ctl binary
      MYTTY_SURFACE_ID     this pane's own pane ID, the default --anchor
      MYTTY_CONTROL_SOCKET absolute path of the control socket mytty-ctl talks to

    Prefer "$MYTTY_CTL_BIN" over a bare `mytty-ctl` unless PATH is confirmed.

    AGENT ORCHESTRATION API (preferred)

    Use these commands to run a team of workers. `agent spawn` creates the
    worker's pane and delivers its launch command and task as one shell
    input, so there's no race with a still-initializing TUI the way a manual
    split + send has. Prefer this over the low-level pane commands below for
    anything shaped like "run N agents and collect their output."

      agent spawn --provider <codex|claude|cursor> (--task <text> | --task-file <path>)
                  [--anchor <pane-id>] [--direction <left|right|up|down>]
                  [--cwd <path>] [--access <review|workspace-write>] [--label <text>]
        Splits a new pane off --anchor (default: $MYTTY_SURFACE_ID) and
        launches the worker in it. --access review is read-only
        investigation; workspace-write (the default) lets the worker edit
        files. Prints an agentJob response whose job.jobID.rawValue is the
        job ID every other agent command below takes.

      agent wait <job-id> --until <running|attention|completed> [--timeout-seconds <n>]
        Blocks until this exact job's own spawned run reaches the given
        condition -- never a leftover run from a reused pane. Use
        `--until running` for confirmation the worker actually started;
        `--until attention` only resolves for waiting-input/waiting-
        approval; `--until completed` resolves for succeeded/failed/
        disconnected/launch-failed/lost. Default timeout is 120 seconds. A
        provider that never starts (missing executable, a hook integration
        that isn't installed) surfaces as launch-failed within 30 seconds,
        well before the full timeout.

      agent result <job-id>
        Returns the job's latest state plus the pane's current screen text.
        Read this after `agent wait --until completed` to collect what the
        worker did.

      agent send <job-id> <text> [--enter]
        Sends a follow-up instruction to the job's pane by job ID, so a
        correction always reaches the intended worker even if panes were
        reused for something else in between.

      agent focus <job-id>
        Brings the job's pane to the front for a human to look at.

      agent close <job-id>
        Closes the job's pane once it's no longer needed.

    STAGED EXAMPLE: parallel investigation, then implementation, then review

      1. Spawn two read-only investigation workers in parallel:
           job_a=$("$MYTTY_CTL_BIN" agent spawn --provider codex --access review \\
             --task "Investigate why login times out under load." \\
             --label investigate-a | jq -r '.job.jobID.rawValue')
           job_b=$("$MYTTY_CTL_BIN" agent spawn --provider claude --access review \\
             --task "Investigate whether the timeout is client- or server-side." \\
             --label investigate-b | jq -r '.job.jobID.rawValue')

      2. Wait for both -- they ran in parallel, so order doesn't matter:
           "$MYTTY_CTL_BIN" agent wait "$job_a" --until completed
           "$MYTTY_CTL_BIN" agent wait "$job_b" --until completed

      3. Collect both results:
           findings_a=$("$MYTTY_CTL_BIN" agent result "$job_a" | jq -r '.content.text')
           findings_b=$("$MYTTY_CTL_BIN" agent result "$job_b" | jq -r '.content.text')

      4. Spawn a workspace-write implementation worker with the combined
         findings folded into its task:
           job_impl=$("$MYTTY_CTL_BIN" agent spawn --provider codex --access workspace-write \\
             --task "Findings from investigation-a: $findings_a
           Findings from investigation-b: $findings_b
           Fix the login timeout described above." --label implement \\
             | jq -r '.job.jobID.rawValue')
           "$MYTTY_CTL_BIN" agent wait "$job_impl" --until completed

      5. Spawn a review worker after implementation finishes:
           job_review=$("$MYTTY_CTL_BIN" agent spawn --provider claude --access review \\
             --task "Review the changes made for the login timeout fix." \\
             --label review | jq -r '.job.jobID.rawValue')
           "$MYTTY_CTL_BIN" agent wait "$job_review" --until completed

      6. If review finds problems, send a follow-up correction to the
         implementation job instead of spawning a new one:
           "$MYTTY_CTL_BIN" agent send "$job_impl" "Review found: <issue>. Please fix." --enter
           "$MYTTY_CTL_BIN" agent wait "$job_impl" --until completed

      Close every job once its pane is no longer needed, e.g.
      "$MYTTY_CTL_BIN" agent close "$job_a".

    LOW-LEVEL PANE COMMANDS (escape hatch)

    split/send/wait/read/close-pane/focus predate the agent API and still
    work -- they're the right tool for driving a pane by hand (a human is
    watching, or the task doesn't fit "spawn one worker with one task").
    For running a team of workers, prefer `agent spawn`/`agent wait`/
    `agent result` above: they solve the exact races described below.

      1. split       "$MYTTY_CTL_BIN" split "$MYTTY_SURFACE_ID" right --cwd <dir>
         Claim a pane. Give each sub-agent its own directory (ideally a git
         worktree) so they don't fight over the same files.
      2. send <launch-command> --enter   start the agent (see the provider
         table below for the right flags).
      3. send <instructions> --enter     give it the task.
      4. wait --until idle               block until the run finishes.
      5. read                            fetch the pane's screen text.
      6. close-pane, once done with the pane, or focus to hand control back to
         a human.

      PROVIDER LAUNCH COMMANDS

        claude
          launch: claude --permission-mode acceptEdits
          Without this flag Claude Code starts in plan mode, and `send` cannot
          exit plan mode. Bash commands still need approval: `wait --until
          attention`, then `send "2" --enter` to approve.

        codex
          launch: codex -s workspace-write -a never
          No approval prompts, so `wait --until idle` alone is enough.

        cursor
          launch: cursor-agent --force
          `--force` (aka `--yolo`) skips approval prompts. Don't add `--plan`
          unless the pane's job is read-only investigation -- it disables edits.

        antigravity
          launch: normal, no extra flags
          Its hooks never emit approval/input events, so only `wait --until
          idle` ever resolves for it; `wait --until attention` always times out.

      WAIT PITFALLS

        - If the target provider's integration is not enabled in Mytty Settings,
          no agent events reach Mytty at all, and `wait` blocks until it times
          out regardless of condition. This is the single most common
          first-time failure.
        - Cursor never emits an input-requested event. A shell approval instead
          surfaces as `waiting-approval` roughly 10 seconds after the command
          starts, once Mytty's delay-based estimate fires.
        - Sending the task (step 3) right after the launch command (step 2)
          can lose it: the agent's TUI may still be initializing and drops
          input sent before its prompt is drawn. Don't bridge the two with a
          fixed sleep -- read the pane, and if the prompt isn't on screen
          yet, wait briefly and read again before sending. `agent spawn`
          above avoids this race entirely by sending the launch command and
          the task as one shell input.

      INSTRUCTIONS TO GIVE A SUB-AGENT

      When writing the prompt to `send` to a worker pane, include:

        - Stay inside the given working directory; don't touch files outside it.
        - Keep going until the build and tests pass; fix failures yourself
          instead of stopping to ask.
        - If a design choice is ambiguous, pick one, note the choice and the
          reasoning, and continue rather than asking a question back.
        - End with a bulleted summary: changed files, test results, and any
          remaining issues.
      (`agent spawn` appends an equivalent worker contract automatically.)

      RUNNING SEVERAL WORKERS IN PARALLEL

      Give each sub-agent its own `git worktree` so their working directories
      don't collide. `send` has a 64 KiB limit per call, and any newline in the
      text becomes an Enter keypress -- so a long or multi-line instruction
      should be written to a file first and the sub-agent told to read that
      file, rather than passed as one `send` argument.
    """

    /// Everything `agent spawn --task-file <path>` needs to build a
    /// `spawnAgent` request, minus the task text itself — reading the file
    /// is `MyTTYCtl`'s job (see `ControlInvocation.agentSpawnPendingTaskFile`
    /// and `spawnAgentRequest(from:task:)`), not this Foundation-only,
    /// file-system-free parser's.
    public struct PendingAgentSpawnRequest: Equatable, Sendable {
        public let anchorPaneID: String
        public let direction: ControlSplitDirection
        public let provider: AgentWorkerProvider
        public let cwd: String?
        public let access: AgentAccessPolicy
        public let label: String?
        public let taskFilePath: String

        public init(
            anchorPaneID: String,
            direction: ControlSplitDirection,
            provider: AgentWorkerProvider,
            cwd: String?,
            access: AgentAccessPolicy,
            label: String?,
            taskFilePath: String
        ) {
            self.anchorPaneID = anchorPaneID
            self.direction = direction
            self.provider = provider
            self.cwd = cwd
            self.access = access
            self.label = label
            self.taskFilePath = taskFilePath
        }
    }

    /// The request envelope's cap — the same 64 KiB `UnixSocketTransport`
    /// enforces on the server side. Checked here too so an oversized task
    /// fails as a clear CLI error instead of a socket write silently being
    /// truncated/rejected by the server.
    private static let maximumRequestEnvelopeSize = 64 * 1024

    /// The non-socket entry points (`guide`, `--help`/`-h`, no arguments)
    /// resolved before falling back to `parse(_:)` for everything else.
    /// `Sources/MyTTYCtl/main.swift` uses this so `guide` and `--help` never
    /// require `MYTTY_CONTROL_SOCKET` or a running Mytty.
    public enum ControlInvocation: Equatable, Sendable {
        case request(ControlRequest)
        case guide
        case help
        /// `agent spawn --task-file <path>` was parsed but its task text
        /// hasn't been read yet — `MyTTYCtl/main.swift` reads the file and
        /// calls `spawnAgentRequest(from:task:)` to finish building the
        /// request. The app server never sees a caller-selected file path.
        case agentSpawnPendingTaskFile(PendingAgentSpawnRequest)
    }

    public static func parseInvocation(
        _ arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ControlInvocation {
        guard let first = arguments.first else {
            return .help
        }
        switch first {
        case "guide":
            return .guide
        case "--help", "-h":
            return .help
        case "agent":
            return try parseAgentInvocation(
                Array(arguments.dropFirst()),
                environment: environment
            )
        default:
            return .request(try parse(arguments, environment: environment))
        }
    }

    public static func parse(
        _ arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ControlRequest {
        var arguments = arguments
        guard !arguments.isEmpty else {
            throw ControlCommandLineError.invalidArguments(usage)
        }
        let command = arguments.removeFirst()
        return try makeRequest(
            command: command,
            arguments: arguments,
            environment: environment
        )
    }

    /// Finishes building a `spawnAgent` request once `MyTTYCtl` has read
    /// `--task-file`'s contents, applying the same validation `--task`
    /// gets inline (nonempty, fits the request envelope).
    public static func spawnAgentRequest(
        from pending: PendingAgentSpawnRequest,
        task: String
    ) throws -> ControlRequest {
        try makeSpawnAgentRequest(
            anchorPaneID: pending.anchorPaneID,
            direction: pending.direction,
            provider: pending.provider,
            cwd: pending.cwd,
            access: pending.access,
            task: task,
            label: pending.label
        )
    }

    /// The `--timeout-seconds` a `wait`/`agent wait` request carries, if
    /// any — the CLI gives the socket client a little extra slack beyond
    /// this so the connection isn't torn down right as the server's own
    /// timeout fires.
    public static func waitTimeoutSeconds(
        for request: ControlRequest
    ) -> Double? {
        switch request {
        case let .wait(_, _, timeoutSeconds):
            timeoutSeconds
        case let .waitAgent(_, _, timeoutSeconds):
            timeoutSeconds
        default:
            nil
        }
    }

    private static func makeRequest(
        command: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ControlRequest {
        switch command {
        case "list":
            return .list

        case "agent":
            return try makeAgentRequest(
                arguments: arguments,
                environment: environment
            )

        case "new-tab":
            var positional = arguments
            let options = try parseOptions(
                &positional,
                flags: [],
                valued: ["--cwd"]
            )
            guard positional.isEmpty else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl new-tab [--cwd <path>]"
                )
            }
            return .newTab(workingDirectory: options.values["--cwd"])

        case "split":
            var positional = arguments
            let options = try parseOptions(
                &positional,
                flags: [],
                valued: ["--cwd"]
            )
            guard positional.count == 2,
                  let direction = ControlSplitDirection(
                      rawValue: positional[1]
                  )
            else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl split <pane-id> <left|right|up|down> [--cwd <path>]"
                )
            }
            return .split(
                paneID: positional[0],
                direction: direction,
                workingDirectory: options.values["--cwd"]
            )

        case "send":
            var positional = arguments
            let options = try parseOptions(
                &positional,
                flags: ["--enter"],
                valued: []
            )
            guard positional.count == 2 else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl send <pane-id> <text> [--enter]"
                )
            }
            return .send(
                paneID: positional[0],
                text: positional[1],
                pressEnter: options.flags.contains("--enter")
            )

        case "send-key":
            var positional = arguments
            let options = try parseOptions(
                &positional,
                flags: [],
                valued: ["--modifiers"]
            )
            guard positional.count == 2 else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl send-key <pane-id> <key> [--modifiers <mod,mod,...>]"
                )
            }
            let modifiers = options.values["--modifiers"]?
                .split(separator: ",")
                .map(String.init) ?? []
            return .sendKey(
                paneID: positional[0],
                key: positional[1],
                modifiers: modifiers
            )

        case "read":
            guard arguments.count == 1 else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl read <pane-id>"
                )
            }
            return .read(paneID: arguments[0])

        case "wait":
            var positional = arguments
            let options = try parseOptions(
                &positional,
                flags: [],
                valued: ["--until", "--timeout-seconds"]
            )
            guard positional.count == 1,
                  let untilValue = options.values["--until"],
                  let until = ControlWaitCondition(rawValue: untilValue)
            else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl wait <pane-id> --until <idle|attention> [--timeout-seconds <n>]"
                )
            }
            let timeoutSeconds = options.values["--timeout-seconds"]
                .flatMap(Double.init) ?? 120
            return .wait(
                paneID: positional[0],
                until: until,
                timeoutSeconds: timeoutSeconds
            )

        case "close-pane":
            guard arguments.count == 1 else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl close-pane <pane-id>"
                )
            }
            return .closePane(paneID: arguments[0])

        case "focus":
            guard arguments.count == 1 else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl focus <pane-id>"
                )
            }
            return .focus(paneID: arguments[0])

        default:
            throw ControlCommandLineError.invalidArguments(usage)
        }
    }

    // MARK: - agent

    private static let agentUsage = """
    mytty-ctl agent <spawn|wait|result|send|focus|close> [arguments]
    Run `mytty-ctl guide` for the full agent orchestration recipe.
    """

    private static let agentSpawnUsage = """
    mytty-ctl agent spawn --provider <codex|claude|cursor> \
    (--task <text> | --task-file <path>) [--anchor <pane-id>] \
    [--direction <left|right|up|down>] [--cwd <path>] \
    [--access <review|workspace-write>] [--label <text>]
    """

    /// `agent` routed through `parseInvocation`: unlike every other
    /// command, `agent spawn --task-file` can't be resolved to a
    /// `ControlRequest` here — that needs `MyTTYCtl` to read the file
    /// first — so this returns a `ControlInvocation` rather than calling
    /// straight into `makeAgentRequest`.
    private static func parseAgentInvocation(
        _ arguments: [String],
        environment: [String: String]
    ) throws -> ControlInvocation {
        guard let subcommand = arguments.first else {
            throw ControlCommandLineError.invalidArguments(agentUsage)
        }
        guard subcommand == "spawn" else {
            return .request(
                try makeAgentRequest(
                    arguments: arguments,
                    environment: environment
                )
            )
        }
        switch try parseAgentSpawn(
            Array(arguments.dropFirst()),
            environment: environment
        ) {
        case let .task(task, pending):
            return .request(
                try spawnAgentRequest(from: pending, task: task)
            )
        case let .taskFile(pending):
            return .agentSpawnPendingTaskFile(pending)
        }
    }

    private static func makeAgentRequest(
        arguments: [String],
        environment: [String: String]
    ) throws -> ControlRequest {
        var arguments = arguments
        guard !arguments.isEmpty else {
            throw ControlCommandLineError.invalidArguments(agentUsage)
        }
        let subcommand = arguments.removeFirst()

        if subcommand == "spawn" {
            switch try parseAgentSpawn(arguments, environment: environment) {
            case let .task(task, pending):
                return try spawnAgentRequest(from: pending, task: task)
            case .taskFile:
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl agent spawn --task-file requires the "
                        + "mytty-ctl CLI (which reads the file); it cannot "
                        + "be resolved from parse(_:) alone"
                )
            }
        }

        switch subcommand {
        case "wait":
            var positional = arguments
            let options = try parseOptions(
                &positional,
                flags: [],
                valued: ["--until", "--timeout-seconds"]
            )
            guard positional.count == 1,
                  let jobID = AgentJobID(uuidString: positional[0]),
                  let untilValue = options.values["--until"],
                  let until = AgentWaitCondition(rawValue: untilValue)
            else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl agent wait <job-id> --until "
                        + "<running|attention|completed> "
                        + "[--timeout-seconds <n>]"
                )
            }
            let timeoutSeconds = options.values["--timeout-seconds"]
                .flatMap(Double.init) ?? 120
            return .waitAgent(
                jobID: jobID,
                until: until,
                timeoutSeconds: timeoutSeconds
            )

        case "result":
            guard arguments.count == 1,
                  let jobID = AgentJobID(uuidString: arguments[0])
            else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl agent result <job-id>"
                )
            }
            return .agentResult(jobID: jobID)

        case "send":
            var positional = arguments
            let options = try parseOptions(
                &positional,
                flags: ["--enter"],
                valued: []
            )
            guard positional.count == 2,
                  let jobID = AgentJobID(uuidString: positional[0])
            else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl agent send <job-id> <text> [--enter]"
                )
            }
            return .sendAgent(
                jobID: jobID,
                text: positional[1],
                pressEnter: options.flags.contains("--enter")
            )

        case "focus":
            guard arguments.count == 1,
                  let jobID = AgentJobID(uuidString: arguments[0])
            else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl agent focus <job-id>"
                )
            }
            return .focusAgent(jobID: jobID)

        case "close":
            guard arguments.count == 1,
                  let jobID = AgentJobID(uuidString: arguments[0])
            else {
                throw ControlCommandLineError.invalidArguments(
                    "mytty-ctl agent close <job-id>"
                )
            }
            return .closeAgent(jobID: jobID)

        default:
            throw ControlCommandLineError.invalidArguments(agentUsage)
        }
    }

    private enum ParsedAgentSpawn {
        case task(String, PendingAgentSpawnRequest)
        case taskFile(PendingAgentSpawnRequest)
    }

    /// Parses every `agent spawn` option except reading `--task-file`'s
    /// contents, which stays out of this Foundation-parsing-only layer —
    /// see `PendingAgentSpawnRequest`.
    private static func parseAgentSpawn(
        _ arguments: [String],
        environment: [String: String]
    ) throws -> ParsedAgentSpawn {
        var positional = arguments
        let options = try parseOptions(
            &positional,
            flags: [],
            valued: [
                "--anchor", "--direction", "--provider", "--cwd",
                "--access", "--task", "--task-file", "--label",
            ]
        )
        guard positional.isEmpty else {
            throw ControlCommandLineError.invalidArguments(agentSpawnUsage)
        }

        guard let anchorPaneID = options.values["--anchor"]
            ?? environment["MYTTY_SURFACE_ID"],
            !anchorPaneID.isEmpty
        else {
            throw ControlCommandLineError.invalidArguments(
                "mytty-ctl agent spawn requires --anchor <pane-id> (or "
                    + "MYTTY_SURFACE_ID to be set)"
            )
        }

        let directionValue = options.values["--direction"] ?? "right"
        guard let direction = ControlSplitDirection(
            rawValue: directionValue
        ) else {
            throw ControlCommandLineError.invalidArguments(agentSpawnUsage)
        }

        guard let providerValue = options.values["--provider"],
              let provider = AgentWorkerProvider(rawValue: providerValue)
        else {
            throw ControlCommandLineError.invalidArguments(agentSpawnUsage)
        }

        let accessValue = options.values["--access"]
            ?? AgentAccessPolicy.workspaceWrite.rawValue
        guard let access = AgentAccessPolicy(rawValue: accessValue) else {
            throw ControlCommandLineError.invalidArguments(agentSpawnUsage)
        }

        let pending = PendingAgentSpawnRequest(
            anchorPaneID: anchorPaneID,
            direction: direction,
            provider: provider,
            cwd: options.values["--cwd"],
            access: access,
            label: options.values["--label"],
            taskFilePath: options.values["--task-file"] ?? ""
        )

        switch (options.values["--task"], options.values["--task-file"]) {
        case (nil, nil), (.some, .some):
            throw ControlCommandLineError.invalidArguments(
                "mytty-ctl agent spawn requires exactly one of --task or "
                    + "--task-file"
            )
        case let (.some(task), nil):
            return .task(task, pending)
        case (nil, .some):
            return .taskFile(pending)
        }
    }

    private static func makeSpawnAgentRequest(
        anchorPaneID: String,
        direction: ControlSplitDirection,
        provider: AgentWorkerProvider,
        cwd: String?,
        access: AgentAccessPolicy,
        task: String,
        label: String?
    ) throws -> ControlRequest {
        guard !task.isEmpty else {
            throw ControlCommandLineError.invalidArguments(
                "mytty-ctl agent spawn requires a nonempty task"
            )
        }
        let request = ControlRequest.spawnAgent(
            anchorPaneID: anchorPaneID,
            direction: direction,
            provider: provider,
            cwd: cwd,
            access: access,
            task: task,
            label: label
        )
        let encodedSize = (try? ControlMessageCodec.encode(request).count)
            ?? Int.max
        guard encodedSize < maximumRequestEnvelopeSize else {
            throw ControlCommandLineError.invalidArguments(
                "mytty-ctl agent spawn: task is too large to fit in the "
                    + "64 KiB request envelope"
            )
        }
        return request
    }

    private struct ParsedOptions {
        var flags: Set<String> = []
        var values: [String: String] = [:]
    }

    /// Extracts `--flag` and `--key value` options from `arguments` in
    /// place, leaving only positional arguments behind. `flags` names take
    /// no value; `valued` names consume the following argument.
    @discardableResult
    private static func parseOptions(
        _ arguments: inout [String],
        flags: Set<String>,
        valued: Set<String>
    ) throws -> ParsedOptions {
        var result = ParsedOptions()
        var positional: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if flags.contains(argument) {
                result.flags.insert(argument)
                index += 1
            } else if valued.contains(argument) {
                guard index + 1 < arguments.count else {
                    throw ControlCommandLineError.invalidArguments(
                        "\(argument) requires a value"
                    )
                }
                result.values[argument] = arguments[index + 1]
                index += 2
            } else {
                positional.append(argument)
                index += 1
            }
        }
        arguments = positional
        return result
    }
}
