import Testing

@testable import MyTTYCore

@Suite("Agent worktree branch validation")
struct AgentWorktreeValidationTests {
    @Test("accepts an ordinary branch name")
    func acceptsOrdinaryBranch() {
        #expect(AgentWorktreeValidation.isValid("feature-a"))
    }

    @Test("accepts a branch with a slash")
    func acceptsSlashedBranch() {
        #expect(AgentWorktreeValidation.isValid("feat/worker-a"))
    }

    @Test("accepts every allowed character class")
    func acceptsEveryAllowedCharacter() {
        #expect(AgentWorktreeValidation.isValid("Feature_1.2/x-y"))
    }

    @Test("rejects an empty branch")
    func rejectsEmpty() {
        #expect(!AgentWorktreeValidation.isValid(""))
    }

    @Test("rejects a branch over the maximum scalar count")
    func rejectsOverlong() {
        let overlong = String(
            repeating: "a",
            count: AgentWorktreeValidation.maximumScalars + 1
        )
        #expect(!AgentWorktreeValidation.isValid(overlong))
    }

    @Test("accepts a branch exactly at the maximum scalar count")
    func acceptsAtMaximum() {
        let atMaximum = String(
            repeating: "a",
            count: AgentWorktreeValidation.maximumScalars
        )
        #expect(AgentWorktreeValidation.isValid(atMaximum))
    }

    @Test("rejects a disallowed character")
    func rejectsDisallowedCharacter() {
        #expect(!AgentWorktreeValidation.isValid("feat a"))
        #expect(!AgentWorktreeValidation.isValid("feat*a"))
        #expect(!AgentWorktreeValidation.isValid("feat~a"))
        #expect(!AgentWorktreeValidation.isValid("feat\u{0000}a"))
    }

    @Test("rejects a leading hyphen")
    func rejectsLeadingHyphen() {
        #expect(!AgentWorktreeValidation.isValid("-feature"))
    }

    @Test("rejects a leading dot")
    func rejectsLeadingDot() {
        #expect(!AgentWorktreeValidation.isValid(".feature"))
    }

    @Test("rejects a leading or trailing slash")
    func rejectsLeadingOrTrailingSlash() {
        #expect(!AgentWorktreeValidation.isValid("/feature"))
        #expect(!AgentWorktreeValidation.isValid("feature/"))
    }

    @Test("rejects a double dot")
    func rejectsDoubleDot() {
        #expect(!AgentWorktreeValidation.isValid("feature..a"))
    }

    @Test("rejects a double slash")
    func rejectsDoubleSlash() {
        #expect(!AgentWorktreeValidation.isValid("feature//a"))
    }

    @Test("rejects a .lock suffix")
    func rejectsLockSuffix() {
        #expect(!AgentWorktreeValidation.isValid("feature.lock"))
    }

    @Test("rejects a trailing dot")
    func rejectsTrailingDot() {
        #expect(!AgentWorktreeValidation.isValid("feature."))
    }

    @Test("accepts a dot that is not leading or trailing")
    func acceptsInteriorDot() {
        #expect(AgentWorktreeValidation.isValid("release-1.2.3"))
    }
}
