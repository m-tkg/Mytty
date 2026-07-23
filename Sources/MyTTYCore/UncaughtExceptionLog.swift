import Foundation

/// A single captured exception, whether reported to AppKit via
/// `-[NSApplication reportException:]` or truly uncaught. We record these
/// ourselves because the unified log redacts exception reasons by default
/// and a crash under SwiftUI/AppKit interop does not always produce an
/// `.ips` report.
public struct UncaughtExceptionReport: Sendable {
    public let name: String
    public let reason: String?
    public let callStack: [String]
    public let timestamp: Date
    public let applicationVersion: String
    /// Where this report came from, e.g. `"reportException"` or
    /// `"uncaughtHandler"`.
    public let source: String

    public init(
        name: String,
        reason: String?,
        callStack: [String],
        timestamp: Date,
        applicationVersion: String,
        source: String
    ) {
        self.name = name
        self.reason = reason
        self.callStack = callStack
        self.timestamp = timestamp
        self.applicationVersion = applicationVersion
        self.source = source
    }

    /// Maximum length, in UTF-8 code units, kept for `name`/`reason` once
    /// sanitized. Exception reasons can embed arbitrarily large strings
    /// (e.g. a dumped object graph); clamp so a single report cannot blow
    /// out the log file.
    private static let maximumFieldLength = 4096

    /// Renders a readable, self-contained block: timestamp, version,
    /// source, name, reason, and call stack, ending with a separator line
    /// so consecutive reports in the same file stay visually distinct.
    public func rendered() -> String {
        let formattedTimestamp = ISO8601DateFormatter().string(from: timestamp)
        let sanitizedName = Self.sanitize(name)
        let sanitizedReason = reason.map(Self.sanitize) ?? "(no reason)"

        var lines: [String] = [
            "timestamp: \(formattedTimestamp)",
            "version: \(applicationVersion)",
            "source: \(source)",
            "name: \(sanitizedName)",
            "reason: \(sanitizedReason)",
            "call stack:",
        ]
        if callStack.isEmpty {
            lines.append("  (no call stack)")
        } else {
            lines.append(contentsOf: callStack.map { "  \($0)" })
        }
        lines.append(String(repeating: "-", count: 80))
        return lines.joined(separator: "\n") + "\n"
    }

    /// Strips control characters (other than newline/tab) and clamps to
    /// `maximumFieldLength`, following the validation conventions used for
    /// other untrusted, provider-owned strings (see `AgentSessionValidation`).
    private static func sanitize(_ value: String) -> String {
        let filtered = String(String.UnicodeScalarView(value.unicodeScalars.filter {
            $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0)
        }))
        if filtered.utf8.count <= maximumFieldLength {
            return filtered
        }
        return String(filtered.prefix(maximumFieldLength))
    }
}

/// Best-effort append-only log for `UncaughtExceptionReport`s. All
/// operations swallow errors: this runs while the process may be dying, so
/// there is no good way to recover from a failed write, and failing loudly
/// would only replace one crash with another.
public struct UncaughtExceptionLog: Sendable {
    private let fileURL: URL
    private let maximumFileSize: Int

    public init(fileURL: URL, maximumFileSize: Int = 1_000_000) {
        self.fileURL = fileURL
        self.maximumFileSize = maximumFileSize
    }

    /// Appends `report.rendered()` to the log file, creating the parent
    /// directory if needed. If the existing file already exceeds
    /// `maximumFileSize`, it is replaced instead of grown further, so the
    /// log cannot accumulate indefinitely across repeated crashes.
    public func append(_ report: UncaughtExceptionReport) {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        guard let data = report.rendered().data(using: .utf8) else { return }

        let existingSize = (try? fileManager.attributesOfItem(
            atPath: fileURL.path
        )[.size] as? Int) ?? nil
        if let existingSize, existingSize > maximumFileSize {
            try? data.write(to: fileURL, options: .atomic)
            return
        }

        if fileManager.fileExists(atPath: fileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                try? data.write(to: fileURL, options: .atomic)
                return
            }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Best effort; nothing more we can do here.
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
