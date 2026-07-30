import Foundation

/// Validates and normalizes user-entered text for the "Open URL" command.
/// User input is untrusted, so a bare host name gets an `https://` scheme
/// prepended, but only `http`/`https` URLs with a host are ever returned —
/// this keeps `javascript:` and local `file:` URLs out of the browser pane.
public enum BrowserURLInput {
    public static func parse(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace }),
              trimmed.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              })
        else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              let url = components.url
        else { return nil }
        return url
    }
}
