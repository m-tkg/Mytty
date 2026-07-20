import Darwin
import Foundation

public enum AgentEventSocketClientError: Error, Equatable, Sendable {
    case socketPathTooLong
    case socketOperation(Int32)
    case emptyResponse
    case responseTooLarge
    case invalidResponse
}

public struct AgentEventServerResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let inserted: Bool?
    public let error: String?

    public init(ok: Bool, inserted: Bool?, error: String?) {
        self.ok = ok
        self.inserted = inserted
        self.error = error
    }

    public static func success(inserted: Bool) -> Self {
        AgentEventServerResponse(ok: true, inserted: inserted, error: nil)
    }

    public static func failure(code: String) -> Self {
        AgentEventServerResponse(ok: false, inserted: nil, error: code)
    }
}

public struct AgentEventSocketClient: Sendable {
    private static let maximumResponseSize = 64 * 1024
    private static let operationTimeoutSeconds = 5

    public init() {}

    public func send(
        _ envelope: AgentEventEnvelope,
        to socketURL: URL
    ) throws -> AgentEventServerResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var request = try encoder.encode(envelope)
        request.append(0x0A)

        let responseData: Data
        do {
            responseData = try sendRequest(request, to: socketURL.path)
        } catch AgentEventSocketClientError.socketOperation(let code)
            where code == EPIPE || code == ECONNRESET {
            // The server times out a connection whose request hasn't
            // arrived within a couple of seconds and closes it without a
            // response; when this process is starved right after
            // connecting (heavy load), the delayed write then hits
            // EPIPE/ECONNRESET. Events are idempotent by protocol, so
            // retry once on a fresh connection.
            responseData = try sendRequest(request, to: socketURL.path)
        }
        do {
            return try JSONDecoder().decode(
                AgentEventServerResponse.self,
                from: responseData
            )
        } catch {
            throw AgentEventSocketClientError.invalidResponse
        }
    }

    private func sendRequest(
        _ request: Data,
        to socketPath: String
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

        var timeout = timeval(
            tv_sec: Self.operationTimeoutSeconds,
            tv_usec: 0
        )
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0,
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
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
        guard connectResult == 0 else { throw socketError() }

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
                    throw AgentEventSocketClientError.responseTooLarge
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
            throw AgentEventSocketClientError.emptyResponse
        }
        return response
    }

    private func unixAddress(path: String) throws -> sockaddr_un {
        guard path.utf8.count
                < MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        else { throw AgentEventSocketClientError.socketPathTooLong }

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

    private func socketError() -> AgentEventSocketClientError {
        .socketOperation(errno)
    }
}
