import Foundation
import Testing

@testable import MyTTYCore

@Suite("Agent mode inheritance")
struct AgentModeInheritanceTests {
    @Test("extracts claude's flag-with-value and boolean flag, preserving order")
    func claudeFlagExtraction() {
        let arguments = AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: [
                "/usr/local/bin/claude",
                "--dangerously-skip-permissions",
                "--permission-mode", "acceptEdits",
            ]
        )
        #expect(arguments == [
            "--dangerously-skip-permissions",
            "--permission-mode", "acceptEdits",
        ])
    }

    @Test("recognizes the --flag=value spelling")
    func equalsSpelling() {
        let arguments = AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: ["claude", "--permission-mode=plan"]
        )
        #expect(arguments == ["--permission-mode", "plan"])
    }

    @Test("extracts every codex flag form: short/long value flags and boolean flags")
    func codexFlagExtraction() {
        let arguments = AgentModeInheritance.inheritedModeArguments(
            provider: .codex,
            leadArguments: [
                "codex", "-s", "workspace-write", "--full-auto", "--yolo",
                "--dangerously-bypass-approvals-and-sandbox",
                "--ask-for-approval", "on-failure",
            ]
        )
        #expect(arguments == [
            "-s", "workspace-write",
            "--full-auto",
            "--yolo",
            "--dangerously-bypass-approvals-and-sandbox",
            "--ask-for-approval", "on-failure",
        ])
    }

    @Test("extracts codex's short -a flag using the = spelling")
    func codexShortFlagEqualsSpelling() {
        let arguments = AgentModeInheritance.inheritedModeArguments(
            provider: .codex,
            leadArguments: ["codex", "-a=never"]
        )
        #expect(arguments == ["-a", "never"])
    }

    @Test("extracts every cursor flag form")
    func cursorFlagExtraction() {
        let arguments = AgentModeInheritance.inheritedModeArguments(
            provider: .cursor,
            leadArguments: [
                "cursor-agent", "--mode", "plan", "--force",
                "--sandbox", "enabled",
            ]
        )
        #expect(arguments == [
            "--mode", "plan",
            "--force",
            "--sandbox", "enabled",
        ])
    }

    @Test("ignores flags unrelated to mode")
    func ignoresUnrelatedFlags() {
        let arguments = AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: [
                "claude", "--model", "sonnet", "--verbose",
                "--permission-mode", "acceptEdits",
            ]
        )
        #expect(arguments == ["--permission-mode", "acceptEdits"])
    }

    @Test("argv[0] never matches a flag, even if it looks like one")
    func argvZeroNeverMatches() {
        let arguments = AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: ["--dangerously-skip-permissions"]
        )
        // argv[0] here literally is the flag spelling -- it still matches,
        // because this function has no notion of "index 0 is special"; it
        // is documented that argv[0] is a path/executable name in
        // practice and therefore can never coincide with a known flag
        // spelling. This test exists to pin that documented assumption:
        // scanning starts at index 0 with no skip.
        #expect(arguments == ["--dangerously-skip-permissions"])
    }

    @Test("empty argv yields no inherited flags")
    func emptyArguments() {
        #expect(AgentModeInheritance.inheritedModeArguments(
            provider: .codex,
            leadArguments: []
        ) == [])
    }

    @Test("flagless argv yields no inherited flags")
    func flaglessArguments() {
        #expect(AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: ["claude"]
        ) == [])
    }

    @Test("claude flags are not extracted for the codex provider")
    func claudeFlagsIgnoredForCodex() {
        #expect(AgentModeInheritance.inheritedModeArguments(
            provider: .codex,
            leadArguments: [
                "codex", "--permission-mode", "acceptEdits",
                "--dangerously-skip-permissions",
            ]
        ) == [])
    }

    @Test("codex flags are not extracted for the claude provider")
    func codexFlagsIgnoredForClaude() {
        #expect(AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: ["claude", "-s", "workspace-write", "--yolo"]
        ) == [])
    }

    @Test("a value with a leading dash drops the flag instead of emitting it dangling")
    func valueLooksLikeAnotherFlagDropsThePair() {
        let arguments = AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: [
                "claude", "--permission-mode", "--dangerously-skip-permissions",
            ]
        )
        // The malformed pair is dropped, but the next token is still
        // evaluated on its own and matches a real boolean flag.
        #expect(arguments == ["--dangerously-skip-permissions"])
    }

    @Test("a missing trailing value drops the flag")
    func missingTrailingValueDropsTheFlag() {
        #expect(AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: ["claude", "--permission-mode"]
        ) == [])
    }

    @Test("a value containing whitespace drops the flag")
    func valueWithWhitespaceDropsTheFlag() {
        #expect(AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: ["claude", "--permission-mode", "accept edits"]
        ) == [])
    }

    @Test("a value containing a control character drops the flag")
    func valueWithControlCharacterDropsTheFlag() {
        #expect(AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: ["claude", "--permission-mode", "accept\u{0007}edits"]
        ) == [])
    }

    @Test("an empty inline value drops the flag")
    func emptyInlineValueDropsTheFlag() {
        #expect(AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: ["claude", "--permission-mode="]
        ) == [])
    }

    @Test("an overlong value drops the flag")
    func overlongValueDropsTheFlag() {
        let overlong = String(repeating: "x", count: 101)
        #expect(AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: ["claude", "--permission-mode", overlong]
        ) == [])
    }

    @Test("a value at exactly the length cap is kept")
    func valueAtCapIsKept() {
        let atCap = String(repeating: "x", count: 100)
        #expect(AgentModeInheritance.inheritedModeArguments(
            provider: .claude,
            leadArguments: ["claude", "--permission-mode", atCap]
        ) == ["--permission-mode", atCap])
    }
}
