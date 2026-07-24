import Foundation

/// Reads the last `maximumBytes` of a file — how every transcript
/// inspector bounds its parsing work: the newest lines are what describe
/// the session's current state.
enum FileTailReader {
    static func tail(of url: URL, maximumBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let tailSize = min(UInt64(maximumBytes), end)
        guard (try? handle.seek(toOffset: end - tailSize)) != nil else {
            return nil
        }
        return try? handle.readToEnd()
    }
}
