import Foundation

/// Shared validation helpers for provider transcript parsing. Values read
/// from provider-owned files (session identifiers, model labels) are
/// untrusted input, so every inspector clamps length and rejects control
/// characters before surfacing them in the UI.
enum AgentSessionValidation {
    static func identifier(_ value: String?) -> String? {
        guard let value,
              !value.isEmpty,
              value.utf8.count <= 256,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              })
        else { return nil }
        return value
    }

    static func label(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= 128,
              trimmed.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              })
        else { return nil }
        return trimmed
    }

    static let maximumPromptCharacters = 400

    /// Prompt text pulled from a provider transcript, reduced to a single
    /// line of material for the tab-name model: control characters and
    /// newlines collapse into single spaces, and the result is clamped —
    /// prompts can be arbitrarily long, but only their beginning is needed
    /// to tell what the user asked for.
    static func promptText(_ value: String?) -> String? {
        guard let value else { return nil }
        var separators = CharacterSet.whitespacesAndNewlines
        separators.formUnion(.controlCharacters)
        let collapsed = value.unicodeScalars
            .split(whereSeparator: { separators.contains($0) })
            .map(String.init)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maximumPromptCharacters))
    }
}
