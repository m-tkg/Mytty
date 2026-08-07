import Foundation

/// Normalizes each provider's raw subscription-plan string into a short,
/// display-ready label. Every entry point treats its input as untrusted
/// provider data (a JSON field or JWT claim) and follows the same
/// hardening rules as `AgentSessionValidation`: reject empty/oversized
/// input and anything containing control characters before it reaches the
/// UI.
enum AgentPlanNameValidation {
    static let maximumInputLength = 64

    /// Trims whitespace and rejects input that's empty, oversized, or
    /// carries a control character. Returns the trimmed, lowercased value
    /// for case-insensitive matching, or `nil` if the input doesn't pass.
    static func normalizedKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maximumInputLength,
              trimmed.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              })
        else { return nil }
        return trimmed.lowercased()
    }
}

public enum CursorPlanName {
    /// Cursor's `usage-summary` payload reports `membershipType` as a
    /// short slug (`"pro"`, `"pro_plus"`, `"enterprise"`, …). Known slugs
    /// map to a display label; anything else is accepted only if it looks
    /// like a plain plan name (letters/digits/space/`+`/`-`/`_`, 1-32
    /// chars) and rendered capitalized with underscores turned to spaces.
    public static func resolve(membershipType: String?) -> String? {
        guard let key = AgentPlanNameValidation.normalizedKey(membershipType)
        else { return nil }
        switch key {
        case "free", "hobby": return "Free"
        case "pro": return "Pro"
        case "pro_plus", "pro plus", "pro-plus": return "Pro+"
        case "ultra": return "Ultra"
        case "team": return "Team"
        case "enterprise", "business": return "Enterprise"
        default: return fallbackLabel(key)
        }
    }

    private static func fallbackLabel(_ key: String) -> String? {
        guard key.count <= 32,
              key.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0)
                      || $0 == " " || $0 == "+" || $0 == "-" || $0 == "_"
              })
        else { return nil }
        let words = key
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let label = words.joined(separator: " ")
        return label.isEmpty ? nil : label
    }
}

public enum ClaudePlanName {
    /// Mirrors CodexBar's `ClaudePlan` resolution: `subscriptionType` wins
    /// when present and recognized; otherwise fall back to
    /// `rateLimitTier`. Both are matched on whole words so a tier like
    /// `default_claude_max_5x` is read as "max" plus a "5x" multiplier
    /// rather than a substring match on "max" inside some unrelated
    /// value.
    public static func resolve(
        subscriptionType: String?,
        rateLimitTier: String?
    ) -> String? {
        if let resolved = resolve(single: subscriptionType, rateLimitTier: rateLimitTier) {
            return resolved
        }
        return resolve(single: rateLimitTier, rateLimitTier: rateLimitTier)
    }

    private static func resolve(
        single value: String?,
        rateLimitTier: String?
    ) -> String? {
        guard let key = AgentPlanNameValidation.normalizedKey(value)
        else { return nil }
        let words = Set(key.split(whereSeparator: { !$0.isLetter && !$0.isNumber }))

        if words.contains("max") {
            if let multiplier = maxMultiplier(rateLimitTier) {
                return "Max \(multiplier)"
            }
            return "Max"
        }
        if words.contains("pro") { return "Pro" }
        if words.contains("team") { return "Team" }
        if words.contains("enterprise") { return "Enterprise" }
        if words.contains("ultra") { return "Ultra" }
        return nil
    }

    /// Pulls a `<digits>x` multiplier out of a rate-limit tier like
    /// `default_claude_max_20x`: the word immediately after `max`.
    private static func maxMultiplier(_ rateLimitTier: String?) -> String? {
        guard let key = AgentPlanNameValidation.normalizedKey(rateLimitTier)
        else { return nil }
        let words = key.split(whereSeparator: { $0 == "_" || $0 == " " || $0 == "-" })
        guard let maxIndex = words.firstIndex(of: "max"),
              words.index(after: maxIndex) < words.endIndex
        else { return nil }
        let candidate = words[words.index(after: maxIndex)]
        guard candidate.hasSuffix("x"),
              candidate.count > 1,
              candidate.dropLast().allSatisfy(\.isNumber)
        else { return nil }
        return String(candidate)
    }
}

public enum CodexPlanName {
    /// Values seen in Codex's `chatgpt_plan_type` claim: `plus`, `pro`,
    /// `team`, `enterprise`, `free`, `business`.
    public static func resolve(planType: String?) -> String? {
        guard let key = AgentPlanNameValidation.normalizedKey(planType)
        else { return nil }
        switch key {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise", "business": return "Enterprise"
        case "free": return "Free"
        default: return nil
        }
    }
}
