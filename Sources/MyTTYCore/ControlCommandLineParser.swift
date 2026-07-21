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
      MYTTY_SURFACE_ID     this pane's own pane ID, usable as "self"
      MYTTY_CONTROL_SOCKET absolute path of the control socket mytty-ctl talks to

    Prefer "$MYTTY_CTL_BIN" over a bare `mytty-ctl` unless PATH is confirmed.

    BASIC FLOW

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
        yet, wait briefly and read again before sending.

    INSTRUCTIONS TO GIVE A SUB-AGENT

    When writing the prompt to `send` to a worker pane, include:

      - Stay inside the given working directory; don't touch files outside it.
      - Keep going until the build and tests pass; fix failures yourself
        instead of stopping to ask.
      - If a design choice is ambiguous, pick one, note the choice and the
        reasoning, and continue rather than asking a question back.
      - End with a bulleted summary: changed files, test results, and any
        remaining issues.

    RUNNING SEVERAL WORKERS IN PARALLEL

    Give each sub-agent its own `git worktree` so their working directories
    don't collide. `send` has a 64 KiB limit per call, and any newline in the
    text becomes an Enter keypress -- so a long or multi-line instruction
    should be written to a file first and the sub-agent told to read that
    file, rather than passed as one `send` argument.
    """

    /// The non-socket entry points (`guide`, `--help`/`-h`, no arguments)
    /// resolved before falling back to `parse(_:)` for everything else.
    /// `Sources/MyTTYCtl/main.swift` uses this so `guide` and `--help` never
    /// require `MYTTY_CONTROL_SOCKET` or a running Mytty.
    public enum ControlInvocation: Equatable, Sendable {
        case request(ControlRequest)
        case guide
        case help
    }

    public static func parseInvocation(
        _ arguments: [String]
    ) throws -> ControlInvocation {
        guard let first = arguments.first else {
            return .help
        }
        switch first {
        case "guide":
            return .guide
        case "--help", "-h":
            return .help
        default:
            return .request(try parse(arguments))
        }
    }

    public static func parse(_ arguments: [String]) throws -> ControlRequest {
        var arguments = arguments
        guard !arguments.isEmpty else {
            throw ControlCommandLineError.invalidArguments(usage)
        }
        let command = arguments.removeFirst()
        return try makeRequest(command: command, arguments: arguments)
    }

    /// The `--timeout-seconds` a `wait` request carries, if any — the CLI
    /// gives the socket client a little extra slack beyond this so the
    /// connection isn't torn down right as the server's own timeout fires.
    public static func waitTimeoutSeconds(
        for request: ControlRequest
    ) -> Double? {
        guard case let .wait(_, _, timeoutSeconds) = request else {
            return nil
        }
        return timeoutSeconds
    }

    private static func makeRequest(
        command: String,
        arguments: [String]
    ) throws -> ControlRequest {
        switch command {
        case "list":
            return .list

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
