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
    }
} catch {
    let message = "mytty-agent-hook: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}
