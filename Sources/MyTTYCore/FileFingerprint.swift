import Foundation

/// Shared helpers for cheaply detecting whether a file has changed, without
/// re-reading its contents. Used by the agent session pollers/inspectors to
/// avoid redundant parses.
public enum FileFingerprint {
    /// A modification-time + size pair used to detect whether a file changed.
    public static func of(_ url: URL) -> (mtime: Date, size: UInt64)? {
        guard let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        ),
              let mtime = values.contentModificationDate,
              let size = values.fileSize
        else { return nil }
        return (mtime, UInt64(size))
    }

    /// The file's modification date, falling back to `.distantPast` when it
    /// cannot be read.
    public static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate) ?? .distantPast
    }
}
