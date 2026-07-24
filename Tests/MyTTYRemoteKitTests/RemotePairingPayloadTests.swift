import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite("Remote pairing QR payload")
struct RemotePairingPayloadTests {
    @Test("round-trips through its URL string")
    func roundTripsThroughURLString() {
        let token = RemotePairing.generateCode().value
        let payload = RemotePairingPayload(token: token)
        let urlString = payload.urlString()

        let parsed = RemotePairingPayload.parse(urlString)
        #expect(parsed == payload)
    }

    @Test("encodes the scheme, host, version, and token in the URL")
    func encodesExpectedURLShape() {
        let payload = RemotePairingPayload(
            token: "abcdefghijklmnopqrstuvwxyz0123456789ABCDEF"
        )
        let urlString = payload.urlString()
        #expect(urlString.hasPrefix("mytty://pair?"))
        #expect(urlString.contains("v=1"))
        #expect(
            urlString.contains(
                "s=abcdefghijklmnopqrstuvwxyz0123456789ABCDEF"
            )
        )
    }

    @Test("rejects an unsupported version")
    func rejectsUnsupportedVersion() {
        let parsed = RemotePairingPayload.parse(
            "mytty://pair?v=99&s=abcdefghijklmnopqrstuvwxyz0123456789ABC"
        )
        #expect(parsed == nil)
    }

    @Test("rejects a missing token")
    func rejectsMissingToken() {
        let parsed = RemotePairingPayload.parse("mytty://pair?v=1")
        #expect(parsed == nil)
    }

    @Test("rejects a token that is too short to have come from the generator")
    func rejectsTooShortToken() {
        let parsed = RemotePairingPayload.parse("mytty://pair?v=1&s=short")
        #expect(parsed == nil)
    }

    @Test("rejects an oversized token")
    func rejectsOversizedToken() {
        let hugeToken = String(repeating: "a", count: 10_000)
        let parsed = RemotePairingPayload.parse(
            "mytty://pair?v=1&s=\(hugeToken)"
        )
        #expect(parsed == nil)
    }

    @Test("rejects a token with characters outside the base64url charset")
    func rejectsTokenWithInvalidCharacters() {
        let parsed = RemotePairingPayload.parse(
            "mytty://pair?v=1&s=not/a valid+token=="
        )
        #expect(parsed == nil)
    }

    @Test("rejects the wrong scheme")
    func rejectsWrongScheme() {
        let parsed = RemotePairingPayload.parse(
            "https://pair?v=1&s=abcdefghijklmnopqrstuvwxyz0123456789ABC"
        )
        #expect(parsed == nil)
    }

    @Test("rejects the wrong host")
    func rejectsWrongHost() {
        let parsed = RemotePairingPayload.parse(
            "mytty://not-pair?v=1&s=abcdefghijklmnopqrstuvwxyz0123456789ABC"
        )
        #expect(parsed == nil)
    }

    @Test("rejects arbitrary junk that isn't a URL at all")
    func rejectsJunk() {
        #expect(RemotePairingPayload.parse("") == nil)
        #expect(RemotePairingPayload.parse("not a url") == nil)
        #expect(RemotePairingPayload.parse("¯\\_(ツ)_/¯") == nil)
    }

    @Test("is case-insensitive on scheme and host")
    func isCaseInsensitiveOnSchemeAndHost() {
        let parsed = RemotePairingPayload.parse(
            "MYTTY://PAIR?v=1&s=abcdefghijklmnopqrstuvwxyz0123456789ABC"
        )
        #expect(parsed?.token == "abcdefghijklmnopqrstuvwxyz0123456789ABC")
    }
}
