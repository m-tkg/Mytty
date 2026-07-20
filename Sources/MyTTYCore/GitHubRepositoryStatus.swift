import Foundation

public struct GitHubRepositoryStatus: Equatable, Sendable {
    public let pageURL: URL
    public let branchName: String

    public init(pageURL: URL, branchName: String) {
        self.pageURL = pageURL
        self.branchName = branchName
    }
}

enum GitHubRemoteURL {
    static func pageURL(from remote: String) -> URL? {
        let remote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if remote.hasPrefix("git@github.com:") {
            path = String(remote.dropFirst("git@github.com:".count))
        } else {
            guard let components = URLComponents(string: remote),
                  let scheme = components.scheme?.lowercased(),
                  ["git", "http", "https", "ssh"].contains(scheme),
                  components.host?.lowercased() == "github.com",
                  components.query == nil,
                  components.fragment == nil
            else { return nil }
            path = components.path
        }

        var parts = path.split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[1].hasSuffix(".git") {
            parts[1].removeLast(4)
        }
        guard parts.allSatisfy(isValidPathComponent) else { return nil }

        var result = URLComponents()
        result.scheme = "https"
        result.host = "github.com"
        result.path = "/\(parts[0])/\(parts[1])"
        return result.url
    }

    private static func isValidPathComponent(_ component: String) -> Bool {
        guard !component.isEmpty, component != ".", component != ".." else {
            return false
        }
        return component.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
                || "-_.".unicodeScalars.contains($0)
        }
    }
}

public protocol GitCommandRunning: Sendable {
    func output(in directory: URL, arguments: [String]) async -> String?
}

public struct GitHubRepositoryLoader: Sendable {
    private let runner: any GitCommandRunning

    public init(runner: any GitCommandRunning = GitProcessRunner()) {
        self.runner = runner
    }

    public func load(from directory: URL) async -> GitHubRepositoryStatus? {
        guard directory.isFileURL else { return nil }
        guard let remoteOutput = await runner.output(
            in: directory,
            arguments: ["remote"]
        ) else { return nil }

        var remotes = remoteOutput.split(whereSeparator: \.isNewline)
            .map(String.init)
        if let origin = remotes.firstIndex(of: "origin") {
            remotes.insert(remotes.remove(at: origin), at: 0)
        }
        for remoteName in remotes.prefix(32) {
            guard let remote = await runner.output(
                in: directory,
                arguments: ["remote", "get-url", remoteName]
            ),
                  let pageURL = GitHubRemoteURL.pageURL(from: remote)
            else { continue }
            var branch = trimmed(await runner.output(
                in: directory,
                arguments: ["branch", "--show-current"]
            ))
            if branch?.isEmpty != false {
                branch = trimmed(await runner.output(
                    in: directory,
                    arguments: ["rev-parse", "--short", "HEAD"]
                ))
            }
            guard let branch, !branch.isEmpty else { return nil }
            return GitHubRepositoryStatus(pageURL: pageURL, branchName: branch)
        }
        return nil
    }

    private func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct GitProcessRunner: GitCommandRunning {
    private static let executable = URL(fileURLWithPath: "/usr/bin/git")
    private static let maximumOutputBytes = 64 * 1_024
    private static let timeout: DispatchTimeInterval = .seconds(2)

    public init() {}

    public func output(in directory: URL, arguments: [String]) async -> String? {
        let directory = directory.standardizedFileURL
        return await Task.detached(priority: .utility) {
            Self.run(in: directory, arguments: arguments)
        }.value
    }

    private static func run(
        in directory: URL,
        arguments: [String]
    ) -> String? {
        let process = Process()
        let output = Pipe()
        let finished = DispatchSemaphore(value: 0)
        let buffer = GitOutputBuffer(maximumBytes: maximumOutputBytes)
        process.executableURL = executable
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { handle in
            buffer.append(handle.availableData)
        }
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            _ = finished.wait(timeout: .now() + .milliseconds(250))
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        output.fileHandleForReading.readabilityHandler = nil
        buffer.append(output.fileHandleForReading.readDataToEndOfFile())
        guard process.terminationStatus == 0,
              let data = buffer.data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private final class GitOutputBuffer: @unchecked Sendable {
    private let maximumBytes: Int
    private let lock = NSLock()
    private var storage = Data()
    private var overflowed = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    var data: Data? {
        lock.withLock { overflowed ? nil : storage }
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            guard !overflowed else { return }
            guard storage.count + data.count <= maximumBytes else {
                overflowed = true
                storage.removeAll(keepingCapacity: false)
                return
            }
            storage.append(data)
        }
    }
}
