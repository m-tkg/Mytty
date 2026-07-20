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
    On failure it prints a message to stderr and exits 1. See
    docs/reference/mytty-ctl.md for the JSON shapes and the pane-team recipes this is
    meant to support.
    """

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
