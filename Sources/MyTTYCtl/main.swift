import Foundation
import MyTTYCore

private enum ControlCommandError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case requestFailed(String)
    case appNotRunning
    case missingSocketEnvironment

    var description: String {
        switch self {
        case let .invalidArguments(usage):
            "usage: \(usage)"
        case let .requestFailed(code):
            "mytty rejected the request: \(code)"
        case .appNotRunning:
            "Mytty isn't running (or the AI control socket isn't ready yet)"
        case .missingSocketEnvironment:
            "MYTTY_CONTROL_SOCKET is not set — run mytty-ctl from inside a "
                + "Mytty pane, or set it manually to Mytty's AI control "
                + "socket path"
        }
    }
}

private func run() throws {
    let request: ControlRequest
    do {
        request = try ControlCommandLineParser.parse(
            Array(CommandLine.arguments.dropFirst())
        )
    } catch let ControlCommandLineError.invalidArguments(usage) {
        throw ControlCommandError.invalidArguments(usage)
    }

    guard let socketPath = ProcessInfo.processInfo.environment[
        AgentHookBridge.controlSocketEnvironmentKey
    ] else {
        throw ControlCommandError.missingSocketEnvironment
    }
    let socketURL = URL(fileURLWithPath: socketPath, isDirectory: false)

    let response: ControlResponse
    do {
        response = try ControlSocketClient().send(
            request,
            to: socketURL,
            timeoutSeconds: ControlCommandLineParser.waitTimeoutSeconds(
                for: request
            )
        )
    } catch ControlSocketClientError.appNotRunning {
        throw ControlCommandError.appNotRunning
    }

    if case let .failure(code) = response {
        throw ControlCommandError.requestFailed(code)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(response)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("mytty-ctl: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
