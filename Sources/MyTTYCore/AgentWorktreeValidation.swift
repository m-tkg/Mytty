import Foundation

/// Validation for `agent spawn --worktree <branch>`'s branch argument.
/// Mirrors `ControlStatusNoteValidation`'s shape (a pure `isValid`
/// predicate over a short piece of caller-supplied text) but enforces git's
/// own branch-name shape rather than "no control characters": the branch is
/// about to become both a `git worktree add` argument and a path component
/// (see `AgentWorktreePlan.worktreePath`), so anything git itself would
/// reject, or anything that could escape the derived worktree directory, is
/// rejected here first with the CLI-facing `invalid-worktree-branch`
/// failure code rather than surfacing as an opaque `git` failure.
public enum AgentWorktreeValidation {
    public static let maximumScalars = 100

    public static func isValid(_ branch: String) -> Bool {
        guard !branch.isEmpty,
              branch.unicodeScalars.count <= maximumScalars,
              branch.unicodeScalars.allSatisfy(isAllowedScalar)
        else { return false }
        guard !branch.hasPrefix("-"), !branch.hasPrefix(".") else {
            return false
        }
        guard !branch.hasPrefix("/"), !branch.hasSuffix("/") else {
            return false
        }
        guard !branch.contains(".."), !branch.contains("//") else {
            return false
        }
        guard !branch.hasSuffix(".lock"), !branch.hasSuffix(".") else {
            return false
        }
        return true
    }

    /// `[A-Za-z0-9._/-]` — everything a worktree branch may contain.
    private static func isAllowedScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41 ... 0x5A, // A-Z
             0x61 ... 0x7A, // a-z
             0x30 ... 0x39: // 0-9
            true
        default:
            scalar == "." || scalar == "_" || scalar == "/" || scalar == "-"
        }
    }
}
