import Foundation

/// The payload encoded in the Mac's pairing QR code and decoded by the iOS
/// app's camera scanner. Carries only the high-entropy pairing token: the
/// phone already knows how to find the Mac on its own (Bonjour discovery
/// or manual host/port entry in `PairingView`), so nothing else needs to
/// ride along in the QR image.
///
/// Encoded as a `mytty://pair?v=<version>&s=<token>` URL rather than raw
/// JSON, versioned from the start so a future field can be added without
/// breaking older phones (which simply won't recognize a newer version and
/// will ask the user to update).
public struct RemotePairingPayload: Equatable, Sendable {
    public static let currentVersion = 1

    private static let scheme = "mytty"
    private static let host = "pair"
    /// Tokens are 256-bit values base64url-encoded (~43 characters); this
    /// bounds well above that so a future larger token still fits, while
    /// still rejecting a maliciously oversized scan before it's used.
    private static let maximumTokenLength = 512
    /// Below this a scanned token could never have come from
    /// `RemotePairing.generateCode`; rejecting it early avoids deriving a
    /// preshared key from something trivially guessable.
    private static let minimumTokenLength = 16
    private static let tokenCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )

    public let version: Int
    public let token: String

    public init(
        token: String,
        version: Int = RemotePairingPayload.currentVersion
    ) {
        self.version = version
        self.token = token
    }

    /// The string encoded into the QR code shown in Settings.
    public func urlString() -> String {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [
            URLQueryItem(name: "v", value: String(version)),
            URLQueryItem(name: "s", value: token),
        ]
        return components.url?.absoluteString
            ?? "\(Self.scheme)://\(Self.host)?v=\(version)&s=\(token)"
    }

    /// Strictly validates a scanned QR string before trusting it: a
    /// camera can scan literally anything, so this rejects malformed
    /// URLs, an unsupported version, and a token outside the expected
    /// length/charset rather than passing junk through to the network
    /// layer.
    public static func parse(_ string: String) -> RemotePairingPayload? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= maximumTokenLength + 64,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == host
        else { return nil }

        let items = components.queryItems ?? []
        guard let versionString = items.first(where: { $0.name == "v" })?.value,
              let version = Int(versionString),
              version == currentVersion
        else { return nil }

        guard let token = items.first(where: { $0.name == "s" })?.value,
              isValidToken(token)
        else { return nil }

        return RemotePairingPayload(token: token, version: version)
    }

    private static func isValidToken(_ token: String) -> Bool {
        guard token.utf8.count >= minimumTokenLength,
              token.utf8.count <= maximumTokenLength
        else { return false }
        return token.unicodeScalars.allSatisfy {
            tokenCharacters.contains($0)
        }
    }
}
