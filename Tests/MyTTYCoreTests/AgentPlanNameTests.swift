import Testing

@testable import MyTTYCore

@Suite("Agent plan name normalization")
struct AgentPlanNameTests {
    @Test("resolves known Cursor membership types")
    func cursorKnownValues() {
        #expect(CursorPlanName.resolve(membershipType: "free") == "Free")
        #expect(CursorPlanName.resolve(membershipType: "hobby") == "Free")
        #expect(CursorPlanName.resolve(membershipType: "pro") == "Pro")
        #expect(CursorPlanName.resolve(membershipType: "pro_plus") == "Pro+")
        #expect(CursorPlanName.resolve(membershipType: "pro plus") == "Pro+")
        #expect(CursorPlanName.resolve(membershipType: "ultra") == "Ultra")
        #expect(CursorPlanName.resolve(membershipType: "team") == "Team")
        #expect(CursorPlanName.resolve(membershipType: "enterprise") == "Enterprise")
        #expect(CursorPlanName.resolve(membershipType: "business") == "Enterprise")
        // Case-insensitive, whitespace-trimmed.
        #expect(CursorPlanName.resolve(membershipType: "  PRO  ") == "Pro")
    }

    @Test("renders an unrecognized Cursor plan as a capitalized fallback")
    func cursorUnknownFallback() {
        #expect(CursorPlanName.resolve(membershipType: "student_plan") == "Student Plan")
        #expect(CursorPlanName.resolve(membershipType: "beta-tester") == "Beta-tester")
    }

    @Test("rejects an unsafe or malformed Cursor plan string")
    func cursorUnsafeFallback() {
        #expect(CursorPlanName.resolve(membershipType: "weird$plan!") == nil)
        #expect(
            CursorPlanName.resolve(
                membershipType: String(repeating: "a", count: 40)
            ) == nil
        )
    }

    @Test("resolves known Claude subscription types")
    func claudeKnownValues() {
        #expect(
            ClaudePlanName.resolve(subscriptionType: "pro", rateLimitTier: nil)
                == "Pro"
        )
        #expect(
            ClaudePlanName.resolve(subscriptionType: "team", rateLimitTier: nil)
                == "Team"
        )
        #expect(
            ClaudePlanName.resolve(subscriptionType: "enterprise", rateLimitTier: nil)
                == "Enterprise"
        )
        #expect(
            ClaudePlanName.resolve(subscriptionType: "ultra", rateLimitTier: nil)
                == "Ultra"
        )
    }

    @Test("renders Max with its rate-limit-tier multiplier")
    func claudeMaxMultiplier() {
        #expect(
            ClaudePlanName.resolve(
                subscriptionType: "max",
                rateLimitTier: "default_claude_max_5x"
            ) == "Max 5x"
        )
        #expect(
            ClaudePlanName.resolve(
                subscriptionType: "max",
                rateLimitTier: "default_claude_max_20x"
            ) == "Max 20x"
        )
        // The multiplier can also come from the fallback field alone.
        #expect(
            ClaudePlanName.resolve(
                subscriptionType: nil,
                rateLimitTier: "default_claude_max_20x"
            ) == "Max 20x"
        )
        // No multiplier in the tier: plain "Max".
        #expect(
            ClaudePlanName.resolve(subscriptionType: "max", rateLimitTier: nil)
                == "Max"
        )
        #expect(
            ClaudePlanName.resolve(
                subscriptionType: "max",
                rateLimitTier: "default_claude_pro"
            ) == "Max"
        )
    }

    @Test("prefers subscriptionType over rateLimitTier when both resolve")
    func claudeSubscriptionTypeWins() {
        #expect(
            ClaudePlanName.resolve(
                subscriptionType: "pro",
                rateLimitTier: "default_claude_max_20x"
            ) == "Pro"
        )
    }

    @Test("falls back to rateLimitTier when subscriptionType is unrecognized")
    func claudeFallsBackToRateLimitTier() {
        #expect(
            ClaudePlanName.resolve(
                subscriptionType: "mystery",
                rateLimitTier: "default_claude_team"
            ) == "Team"
        )
        #expect(
            ClaudePlanName.resolve(subscriptionType: nil, rateLimitTier: "claude_pro_tier")
                == "Pro"
        )
    }

    @Test("returns nil for an unrecognized Claude plan")
    func claudeUnknown() {
        #expect(
            ClaudePlanName.resolve(subscriptionType: "mystery", rateLimitTier: nil) == nil
        )
        #expect(ClaudePlanName.resolve(subscriptionType: nil, rateLimitTier: nil) == nil)
    }

    @Test("resolves known Codex plan types")
    func codexKnownValues() {
        #expect(CodexPlanName.resolve(planType: "plus") == "Plus")
        #expect(CodexPlanName.resolve(planType: "pro") == "Pro")
        #expect(CodexPlanName.resolve(planType: "team") == "Team")
        #expect(CodexPlanName.resolve(planType: "enterprise") == "Enterprise")
        #expect(CodexPlanName.resolve(planType: "business") == "Enterprise")
        #expect(CodexPlanName.resolve(planType: "free") == "Free")
    }

    @Test("returns nil for an unrecognized Codex plan")
    func codexUnknown() {
        #expect(CodexPlanName.resolve(planType: "mystery") == nil)
    }

    @Test("rejects empty, oversized, and control-character input across providers")
    func hardening() {
        #expect(CursorPlanName.resolve(membershipType: "") == nil)
        #expect(ClaudePlanName.resolve(subscriptionType: "", rateLimitTier: "") == nil)
        #expect(CodexPlanName.resolve(planType: "") == nil)

        let oversized = String(repeating: "x", count: 65)
        #expect(CursorPlanName.resolve(membershipType: oversized) == nil)
        #expect(
            ClaudePlanName.resolve(subscriptionType: oversized, rateLimitTier: nil) == nil
        )
        #expect(CodexPlanName.resolve(planType: oversized) == nil)

        let withControlCharacter = "pro\u{0007}"
        #expect(CursorPlanName.resolve(membershipType: withControlCharacter) == nil)
        #expect(
            ClaudePlanName.resolve(
                subscriptionType: withControlCharacter,
                rateLimitTier: nil
            ) == nil
        )
        #expect(CodexPlanName.resolve(planType: withControlCharacter) == nil)
    }

    @Test("returns nil for nil input across providers")
    func nilInput() {
        #expect(CursorPlanName.resolve(membershipType: nil) == nil)
        #expect(ClaudePlanName.resolve(subscriptionType: nil, rateLimitTier: nil) == nil)
        #expect(CodexPlanName.resolve(planType: nil) == nil)
    }
}
