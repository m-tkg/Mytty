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
}
