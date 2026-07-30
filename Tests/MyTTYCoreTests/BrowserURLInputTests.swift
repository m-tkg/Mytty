import Foundation
import Testing

@testable import MyTTYCore

@Suite("Browser URL input")
struct BrowserURLInputTests {
    @Test("adds https to a bare host")
    func addsScheme() throws {
        let url = try #require(BrowserURLInput.parse("example.com"))
        #expect(url.absoluteString == "https://example.com")
    }

    @Test("keeps an explicit http scheme")
    func keepsHTTP() throws {
        let url = try #require(BrowserURLInput.parse("http://example.com"))
        #expect(url.scheme == "http")
    }

    @Test("keeps an explicit https scheme")
    func keepsHTTPS() throws {
        let url = try #require(BrowserURLInput.parse("https://example.com"))
        #expect(url.scheme == "https")
    }

    @Test("trims surrounding whitespace")
    func trims() throws {
        let url = try #require(
            BrowserURLInput.parse("  https://example.com  ")
        )
        #expect(url.absoluteString == "https://example.com")
    }

    @Test("rejects empty input")
    func rejectsEmpty() {
        #expect(BrowserURLInput.parse("") == nil)
        #expect(BrowserURLInput.parse("   ") == nil)
    }

    @Test("rejects a file URL")
    func rejectsFileScheme() {
        #expect(BrowserURLInput.parse("file:///etc/passwd") == nil)
    }

    @Test("rejects a javascript URL")
    func rejectsJavascriptScheme() {
        #expect(BrowserURLInput.parse("javascript:alert(1)") == nil)
    }

    @Test("rejects input with internal whitespace")
    func rejectsInternalSpace() {
        #expect(BrowserURLInput.parse("example.com/some path") == nil)
    }

    @Test("rejects control characters")
    func rejectsControlCharacters() {
        #expect(BrowserURLInput.parse("example.com/\u{0007}") == nil)
    }

    @Test("rejects a scheme with no host")
    func rejectsMissingHost() {
        #expect(BrowserURLInput.parse("https://") == nil)
    }
}
