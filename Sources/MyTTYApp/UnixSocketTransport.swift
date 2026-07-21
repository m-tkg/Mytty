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
    /// Upper bound on how long `write(_:to:)` will keep retrying a send
    /// that's blocked because the client isn't draining its receive
    /// buffer. Keeps a stalled peer from pinning a `workerQueue` thread
    /// forever instead of eventually giving up like a dead peer would.
    private static let writeTimeoutSeconds: TimeInterval = 10

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

            // On Darwin/BSD, a socket accepted from a non-blocking
            // listener inherits O_NONBLOCK. Clear it so `recv`/`send` on
            // this connection block (bounded by the SO_RCVTIMEO set
            // below and the poll-based timeout in `write(_:to:)`)
            // instead of returning EAGAIN as soon as the kernel buffer
            // is briefly empty or full — a response larger than the
            // socket's send buffer (~8 KiB by default) used to get
            // silently truncated because `write(_:to:)` treated EAGAIN
            // as a hard failure.
            let clientFlags = fcntl(client, F_GETFL)
            if clientFlags >= 0 {
                _ = fcntl(client, F_SETFL, clientFlags & ~O_NONBLOCK)
            }

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

    /// Writes the full response, retrying short writes and — as
    /// defense-in-depth alongside clearing O_NONBLOCK in
    /// `acceptAvailableClients` — waiting for the socket to become
    /// writable again on EAGAIN/EWOULDBLOCK rather than giving up after
    /// a partial send. Bounded by `writeTimeoutSeconds` overall, so a
    /// peer that never drains its receive buffer eventually gets
    /// dropped instead of pinning a worker thread forever; a genuinely
    /// dead peer still fails fast via ECONNRESET/EPIPE.
    private static func write(_ data: Data, to client: Int32) {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress, bytes.count > 0
            else { return }
            var sent = 0
            let deadline = Date().addingTimeInterval(writeTimeoutSeconds)
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
                } else if count < 0,
                          errno == EAGAIN || errno == EWOULDBLOCK {
                    let remaining = deadline.timeIntervalSinceNow
                    guard remaining > 0,
                          waitUntilWritable(client, timeout: remaining)
                    else { return }
                    continue
                } else {
                    return
                }
            }
        }
    }

    /// Blocks until `client` is writable or `timeout` elapses. Returns
    /// `false` on timeout or a poll error, in which case the caller
    /// should give up rather than spin.
    private static func waitUntilWritable(
        _ client: Int32,
        timeout: TimeInterval
    ) -> Bool {
        var pollDescriptor = pollfd(
            fd: client,
            events: Int16(POLLOUT),
            revents: 0
        )
        let timeoutMilliseconds = Int32(
            min(max(timeout, 0), Double(Int32.max) / 1000) * 1000
        )
        let result = poll(&pollDescriptor, 1, timeoutMilliseconds)
        guard result > 0 else { return false }
        return pollDescriptor.revents & Int16(POLLOUT) != 0
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
