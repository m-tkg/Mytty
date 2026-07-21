import Darwin
import Foundation

public enum ControlSocketClientError: Error, Equatable, Sendable {
    case socketPathTooLong
    case socketOperation(Int32)
    case emptyResponse
    case responseTooLarge
    case invalidResponse
    case appNotRunning
}

extension ControlSocketClientError: CustomStringConvertible {
    /// `mytty-ctl`'s top-level `catch` prints errors with `"\(error)"`, so
    /// this is what a caller actually sees on stderr. `.socketOperation`
    /// gets special handling for `EPERM`: that errno almost always means
    /// `connect(2)` itself was denied by the operating system, which in
    /// practice means mytty-ctl is running inside a sandbox -- most
    /// commonly a shell command Codex executes under its own macOS
    /// Seatbelt sandbox (review or workspace-write). The socket file, its
    /// permissions, and `MYTTY_CONTROL_SOCKET` are unaffected; this is
    /// strictly an OS-level denial of the connection attempt, and the
    /// bare errno number alone gives the caller no way to tell that
    /// apart from every other failure mode. Every other errno still gets
    /// `strerror(3)` appended so the raw number is never the only
    /// information given.
    public var description: String {
        switch self {
        case .socketPathTooLong:
            return "socketPathTooLong"
        case let .socketOperation(code):
            return ControlSocketErrorFormatting.socketOperationDescription(
                code
            )
        case .emptyResponse:
            return "emptyResponse"
        case .responseTooLarge:
            return "responseTooLarge"
        case .invalidResponse:
            return "invalidResponse"
        case .appNotRunning:
            return "appNotRunning"
        }
    }
}

/// Shared with `AgentEventSocketClientError`, whose `.socketOperation` case
/// fails the exact same way when a provider's hook runs inside a sandbox.
enum ControlSocketErrorFormatting {
    static func socketOperationDescription(_ code: Int32) -> String {
        guard code == EPERM else {
            return "socketOperation(\(code)): "
                + "\(String(cString: strerror(code)))"
        }
        return """
        connect to the Mytty control socket was denied by the operating \
        system (EPERM). This happens when mytty-ctl runs inside a \
        sandbox -- for example, a shell command Codex executes under its \
        own sandbox. Ask for approval to run mytty-ctl outside the \
        sandbox, or re-run it without sandboxing.
        """
    }

    static func hookSocketOperationDescription(_ code: Int32) -> String {
        guard code == EPERM else {
            return "socketOperation(\(code)): "
                + "\(String(cString: strerror(code)))"
        }
        return """
        connect to Mytty's agent-event socket was denied by the operating \
        system (EPERM). This happens when mytty-agent-hook runs inside a \
        sandbox -- for example, a provider hook executed inside its own \
        sandboxed process. Ask for approval to run the hook outside the \
        sandbox, or re-run it without sandboxing.
        """
    }
}

/// Client half of the `mytty-ctl` control protocol: connects to
/// `ApplicationPaths.aiControlSocket`, writes one newline-terminated JSON
/// `ControlRequest`, and blocks for a single newline-terminated JSON
/// `ControlResponse`. Used by the `mytty-ctl` CLI, so `wait` needs a
/// caller-supplied receive timeout well beyond the few-second default used
/// for every other request (the server holds the connection open until the
/// wait condition is met or its own timeout elapses).
public struct ControlSocketClient: Sendable {
    private static let maximumResponseSize = 256 * 1024
    private static let defaultTimeoutSeconds = 5

    public init() {}

    public func send(
        _ request: ControlRequest,
        to socketURL: URL,
        timeoutSeconds: Double? = nil
    ) throws -> ControlResponse {
        var payload = try ControlMessageCodec.encode(request)
        payload.append(0x0A)

        let timeout = timeoutSeconds.map { Int($0.rounded(.up)) + 5 }
            ?? Self.defaultTimeoutSeconds
        let responseData = try sendRequest(
            payload,
            to: socketURL.path,
            timeoutSeconds: timeout
        )
        do {
            return try ControlMessageCodec.decode(responseData)
        } catch {
            throw ControlSocketClientError.invalidResponse
        }
    }

    private func sendRequest(
        _ request: Data,
        to socketPath: String,
        timeoutSeconds: Int
    ) throws -> Data {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw socketError() }
        defer { Darwin.close(descriptor) }

        var noSignal: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else { throw socketError() }

        var sendTimeout = timeval(tv_sec: 5, tv_usec: 0)
        var receiveTimeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &sendTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0,
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else { throw socketError() }

        var address = try unixAddress(path: socketPath)
        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard connectResult == 0 else {
            if errno == ECONNREFUSED || errno == ENOENT {
                throw ControlSocketClientError.appNotRunning
            }
            throw socketError()
        }

        try sendAll(request, descriptor: descriptor)
        guard Darwin.shutdown(descriptor, SHUT_WR) == 0 else {
            throw socketError()
        }
        return try receiveResponse(descriptor: descriptor)
    }

    private func sendAll(
        _ request: Data,
        descriptor: Int32
    ) throws {
        try request.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: sent),
                    bytes.count - sent,
                    0
                )
                if count > 0 {
                    sent += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    throw socketError()
                }
            }
        }
    }

    private func receiveResponse(descriptor: Int32) throws -> Data {
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4 * 1024)
        while true {
            let count = Darwin.recv(
                descriptor,
                &buffer,
                buffer.count,
                0
            )
            if count > 0 {
                response.append(contentsOf: buffer.prefix(count))
                guard response.count <= Self.maximumResponseSize else {
                    throw ControlSocketClientError.responseTooLarge
                }
                if response.contains(0x0A) {
                    break
                }
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw socketError()
            }
        }
        guard !response.isEmpty else {
            throw ControlSocketClientError.emptyResponse
        }
        return response
    }

    private func unixAddress(path: String) throws -> sockaddr_un {
        guard path.utf8.count
                < MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        else { throw ControlSocketClientError.socketPathTooLong }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        return address
    }

    private func socketError() -> ControlSocketClientError {
        if errno == ECONNREFUSED || errno == ENOENT {
            return .appNotRunning
        }
        return .socketOperation(errno)
    }
}
