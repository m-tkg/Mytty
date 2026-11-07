import Darwin
import Foundation
import MyTTYCore

private enum AgentHookCommandError: Error, CustomStringConvertible {
    case invalidArguments
    case payloadTooLarge
    case rejected(String)

    var description: String {
        switch self {
        case .invalidArguments:
            "usage: mytty-agent-hook <codex|claude-code|opencode|antigravity|cursor>"
        case .payloadTooLarge:
            "hook payload exceeds 1 MiB"
        case let .rejected(code):
            "mytty rejected the event: \(code)"
        }
    }
}

/// `mytty-agent-hook antigravity-statusline [--wrap <command>]` is installed
/// as Antigravity's `statusLine.command`. It records the context/quota
/// numbers agy pipes in, then (if the user already had a status line) runs
/// that command with the same input and passes its output through. It never
/// fails loudly: whatever goes to stdout/stderr is drawn in agy's UI.
private func runAntigravityStatusLine(arguments: [String]) -> Never {
    let payload = FileHandle.standardInput.readDataToEndOfFile()
    if let socket = ProcessInfo.processInfo
        .environment[AgentHookBridge.socketEnvironmentKey],
        socket.hasPrefix("/") {
        let store = AntigravityStatusLineStore(
            socketDirectory: URL(fileURLWithPath: socket)
                .deletingLastPathComponent()
        )
        _ = try? store.record(payload: payload)
    }

    guard arguments.count == 2, arguments[0] == "--wrap" else {
        exit(EXIT_SUCCESS)
    }
    // A wrapped command that exits without reading would raise SIGPIPE.
    signal(SIGPIPE, SIG_IGN)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", arguments[1]]
    let input = Pipe()
    process.standardInput = input
    do {
        try process.run()
    } catch {
        exit(EXIT_FAILURE)
    }
    try? input.fileHandleForWriting.write(contentsOf: payload)
    try? input.fileHandleForWriting.close()
    process.waitUntilExit()
    exit(process.terminationStatus)
}

if CommandLine.arguments.count >= 2,
   CommandLine.arguments[1] == AntigravityStatusLineCommand.subcommand {
    runAntigravityStatusLine(
        arguments: Array(CommandLine.arguments.dropFirst(2))
    )
}

do {
    guard CommandLine.arguments.count == 2,
          let provider = AgentProvider(rawValue: CommandLine.arguments[1])
    else { throw AgentHookCommandError.invalidArguments }

    let payload = FileHandle.standardInput.readDataToEndOfFile()
    guard payload.count <= 1024 * 1024 else {
        throw AgentHookCommandError.payloadTooLarge
    }
    guard let delivery = try AgentHookBridge.makeDelivery(
        provider: provider,
        payload: payload,
        environment: ProcessInfo.processInfo.environment,
        occurredAt: Date()
    ) else {
        exit(EXIT_SUCCESS)
    }

    let response = try AgentEventSocketClient().send(
        delivery.envelope,
        to: delivery.socketURL
    )
    guard response.ok else {
        throw AgentHookCommandError.rejected(response.error ?? "unknown")
    }

    if provider == .antigravity {
        let object = try? JSONSerialization.jsonObject(with: payload)
            as? [String: Any]
        let output = object?["fullyIdle"] == nil
            ? "{}\n"
            : "{\"decision\":\"stop\"}\n"
        FileHandle.standardOutput.write(Data(output.utf8))
    } else if provider == .cursor {
        // preToolUse and beforeShellExecution can both return a
        // permission decision; mytty only observes, so it answers with an
        // explicit "no opinion" rather than staying silent — an empty
        // response to preToolUse was observed to make Cursor treat the
        // tool call as denied.
        let object = try? JSONSerialization.jsonObject(with: payload)
            as? [String: Any]
        switch object?["hook_event_name"] as? String {
        case "preToolUse", "beforeShellExecution":
            FileHandle.standardOutput.write(Data("{}\n".utf8))
        default:
            break
        }
    }
} catch {
    let message = "mytty-agent-hook: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}
