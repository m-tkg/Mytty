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
