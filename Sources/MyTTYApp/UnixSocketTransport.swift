import Darwin
import Foundation

enum UnixSocketTransportError: Error {
    case socketPathTooLong
    case socketOperation(Int32)
}

/// Local, unauthenticated Unix-domain socket server shared by
/// `AgentEventServer` (hook events) and `ControlServer` (AI pane control):
/// one request per connection, newline-delimited, replied to via an
/// escaping completion so a handler can defer the reply (`ControlServer`'s
/// `wait` holds a connection open until a condition or timeout).
/// Protection is the socket file's `0600` permission plus the runtime
/// directory's `0700` permission (see `ApplicationFileSystem`) — only the
/// same local user can connect, matching same-user tools like CGEvent.
final class UnixSocketTransport: @unchecked Sendable {
    private static let maximumRequestSize = 64 * 1024

    private let socketURL: URL
    private let queue: DispatchQueue
    private let workerQueue: DispatchQueue
    private let onRequest: @Sendable (
        Data?,
        @escaping @Sendable (Data) -> Void
    ) -> Void
    private let onError: @Sendable (Error) -> Void

    private var serverDescriptor: Int32 = -1
    private var source: DispatchSourceRead?

    init(
        socketURL: URL,
        label: String = "dev.mytty.unix-socket",
        onRequest: @escaping @Sendable (
            Data?,
            @escaping @Sendable (Data) -> Void
        ) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        self.socketURL = socketURL
        self.queue = DispatchQueue(label: label)
        self.workerQueue = DispatchQueue(
            label: "\(label).clients",
            attributes: .concurrent
        )
        self.onRequest = onRequest
        self.onError = onError
    }

    func start() throws {
        guard socketURL.path.utf8.count
                < MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        else { throw UnixSocketTransportError.socketPathTooLong }

        try? FileManager.default.removeItem(at: socketURL)
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw socketError() }

        do {
            var address = try unixAddress(path: socketURL.path)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(
                        descriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                }
            }
            guard bindResult == 0 else { throw socketError() }
            guard chmod(socketURL.path, S_IRUSR | S_IWUSR) == 0 else {
                throw socketError()
            }
            guard Darwin.listen(descriptor, SOMAXCONN) == 0 else {
                throw socketError()
            }
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0,
                  fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
            else { throw socketError() }
        } catch {
            Darwin.close(descriptor)
            try? FileManager.default.removeItem(at: socketURL)
            throw error
        }

        serverDescriptor = descriptor
        let source = DispatchSource.makeReadSource(
            fileDescriptor: descriptor,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.acceptAvailableClients()
        }
        self.source = source
        source.resume()
    }

    func stop() {
        let descriptor = serverDescriptor
        serverDescriptor = -1
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            _ = queue.sync {
                Darwin.close(descriptor)
            }
        }
        try? FileManager.default.removeItem(at: socketURL)
    }

    private func acceptAvailableClients() {
        while serverDescriptor >= 0 {
            let client = Darwin.accept(serverDescriptor, nil, nil)
            if client < 0 {
                if errno != EAGAIN && errno != EWOULDBLOCK {
                    onError(socketError())
                }
                return
            }

            var enabled: Int32 = 1
            setsockopt(
                client,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &enabled,
                socklen_t(MemoryLayout<Int32>.size)
            )
            workerQueue.async { [weak self] in
                self?.readRequest(from: client)
            }
        }
    }

    private func readRequest(from client: Int32) {
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(
            client,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var request = Data()
        var bytes = [UInt8](repeating: 0, count: 4 * 1024)
        while request.count <= Self.maximumRequestSize {
            let count = Darwin.recv(client, &bytes, bytes.count, 0)
            if count > 0 {
                request.append(bytes, count: count)
                if let newline = request.firstIndex(of: 0x0A) {
                    request = Data(request[..<newline])
                    break
                }
            } else if count == 0 {
                break
            } else if errno != EINTR {
                Darwin.close(client)
                return
            }
        }

        let validRequest = request.count <= Self.maximumRequestSize
            ? request
            : nil
        onRequest(validRequest) { response in
            Self.write(response, to: client)
            Darwin.close(client)
        }
    }

    private static func write(_ data: Data, to client: Int32) {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(
                    client,
                    baseAddress.advanced(by: sent),
                    bytes.count - sent,
                    0
                )
                if count > 0 {
                    sent += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }

    private func unixAddress(path: String) throws -> sockaddr_un {
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

    private func socketError() -> UnixSocketTransportError {
        .socketOperation(errno)
    }
}
