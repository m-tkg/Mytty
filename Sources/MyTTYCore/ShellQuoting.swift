import Foundation

/// POSIX single-quote shell quoting, shared by every call site that has to
/// build a `/bin/sh`-safe command line from untrusted text (a resumed
/// session ID, an agent-spawn task). Wrapping in single quotes and escaping
/// embedded single quotes as `'\''` is safe for any byte sequence — no
/// characters are "special" inside single quotes except the quote itself —
/// so this is the one place that needs to get shell escaping right.
public enum ShellQuoting {
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
