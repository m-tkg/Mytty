import Foundation

/// Resolves URLs handed over by Finder ("Open With" document opens and the
/// "Open in Mytty" service) into the working directory a new terminal
/// window should start in.
enum FinderOpenPolicy {
    /// `isDirectory` reports whether the URL is a directory, or nil when the
    /// path does not exist on disk.
    static func workingDirectory(
        for url: URL,
        isDirectory: (URL) -> Bool?
    ) -> URL? {
        guard url.isFileURL else { return nil }
        let standardized = url.standardizedFileURL
        switch isDirectory(standardized) {
        case true:
            return standardized
        case false:
            return standardized.deletingLastPathComponent()
        case nil:
            return nil
        }
    }

    static func workingDirectories(
        for urls: [URL],
        isDirectory: (URL) -> Bool?
    ) -> [URL] {
        var seen = Set<URL>()
        var directories: [URL] = []
        for url in urls {
            guard let directory = workingDirectory(
                for: url,
                isDirectory: isDirectory
            ) else { continue }
            guard seen.insert(directory).inserted else { continue }
            directories.append(directory)
        }
        return directories
    }
}

/// Finder can deliver open requests before `launchApplication` has built the
/// terminal runtime; those must wait, while requests after launch open
/// immediately. `enqueue` returns the URLs that are ready to open now, and
/// `markReady` flushes whatever launch had to hold back.
struct FinderOpenQueue {
    private var isReady = false
    private var pending: [URL] = []

    mutating func enqueue(_ urls: [URL]) -> [URL] {
        guard isReady else {
            pending.append(contentsOf: urls)
            return []
        }
        return urls
    }

    mutating func markReady() -> [URL] {
        isReady = true
        let flushed = pending
        pending = []
        return flushed
    }
}
