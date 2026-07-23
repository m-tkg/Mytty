import AppKit
import MyTTYCore
import os

/// Captures exceptions ourselves instead of relying solely on the system
/// crash reporter. Two things motivated this: the unified log redacts
/// exception reasons by default (`<redacted reason>`), and a crash inside
/// AppKit/ViewBridge during SwiftUI popover presentation has been observed
/// to produce no `.ips` report at all. We log to both a file (durable,
/// unredacted) and `os.Logger` with `.public` privacy (unredacted, visible
/// in Console/`log show` without a sysdiagnose).
enum ExceptionReporting {
    private static let log = Logger(
        subsystem: ApplicationIdentity.bundleIdentifier,
        category: "exception"
    )

    private static let exceptionLog: UncaughtExceptionLog = {
        let paths = ApplicationPaths(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            temporaryDirectory: URL(
                fileURLWithPath: NSTemporaryDirectory(),
                isDirectory: true
            ),
            profile: ApplicationIdentity.pathProfile
        )
        let fileURL = paths.logDirectory
            .appendingPathComponent("uncaught-exceptions.log", isDirectory: false)
        return UncaughtExceptionLog(fileURL: fileURL)
    }()

    /// Records `exception` to the log file and to `os.Logger`, then
    /// returns. Callers remain responsible for whatever happens next
    /// (re-raising, calling through to `super`, or letting the process
    /// terminate).
    static func record(_ exception: NSException, source: String) {
        let report = UncaughtExceptionReport(
            name: exception.name.rawValue,
            reason: exception.reason,
            callStack: exception.callStackSymbols,
            timestamp: Date(),
            applicationVersion: ApplicationIdentity.version.description,
            source: source
        )
        exceptionLog.append(report)

        log.fault(
            """
            uncaught exception (\(source, privacy: .public)): \
            \(report.name, privacy: .public): \
            \(report.reason ?? "(no reason)", privacy: .public)
            """
        )
    }

    /// Installs a process-wide handler for exceptions that reach the top of
    /// the stack without being caught anywhere, including
    /// `-[NSApplication reportException:]`. Must run before `NSApplication`
    /// starts its run loop.
    static func install() {
        // Force the log's lazy initialization now, while the process is
        // healthy, rather than inside a dying process's exception handler.
        _ = exceptionLog
        NSSetUncaughtExceptionHandler { exception in
            ExceptionReporting.record(exception, source: "uncaughtHandler")
        }
    }
}

/// `NSApplication` subclass so we can observe exceptions AppKit itself
/// reports (e.g. from within `-sendEvent:` or SwiftUI/AppKit interop) via
/// `-reportException:`. AppKit funnels many "shouldn't happen" exceptions
/// through this method and swallows them rather than letting them
/// propagate to the uncaught-exception handler, which is why relying on
/// `NSSetUncaughtExceptionHandler` alone is not enough.
final class MyttyApplication: NSApplication {
    override func reportException(_ exception: NSException) {
        ExceptionReporting.record(exception, source: "reportException")
        super.reportException(exception)
    }
}
