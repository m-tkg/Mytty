import Foundation
import Testing
@testable import MyTTYRemoteKit

@Suite
struct RemoteStyledContentTests {
    @Test
    func spanRoundTripsEveryAttribute() throws {
        let span = RemoteTextSpan(
            text: "error",
            foreground: 0xFF0000,
            background: 0x000000,
            bold: true,
            faint: true,
            inverse: true,
            italic: true,
            underline: .curly,
            underlineColor: 0x00FF00,
            strikethrough: true
        )
        let data = try JSONEncoder().encode(span)
        let decoded = try JSONDecoder().decode(RemoteTextSpan.self, from: data)
        #expect(decoded == span)
    }

    @Test
    func aPlainSpanCarriesNothingButItsText() throws {
        let data = try JSONEncoder().encode(RemoteTextSpan(text: "hi"))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        // A styled frame carries one span per colour run per line, so an
        // unstyled run has to stay a single key on the wire.
        #expect(object.keys.sorted() == ["t"])
    }

    @Test
    func spanFromAnOlderHostDecodesWithTheNewAttributesOff() throws {
        let json = #"{"t":"hi","f":16711680,"o":true}"#
        let decoded = try JSONDecoder().decode(
            RemoteTextSpan.self,
            from: Data(json.utf8)
        )
        #expect(decoded.text == "hi")
        #expect(decoded.foreground == 0xFF0000)
        #expect(decoded.bold)
        #expect(!decoded.italic)
        #expect(decoded.underline == .none)
        #expect(decoded.underlineColor == nil)
        #expect(!decoded.strikethrough)
    }

    @Test
    func underlineStylesRoundTripDistinctly() throws {
        for style in [
            RemoteUnderlineStyle.single,
            .double,
            .curly,
            .dotted,
            .dashed,
        ] {
            let span = RemoteTextSpan(text: "x", underline: style)
            let data = try JSONEncoder().encode(span)
            let decoded = try JSONDecoder().decode(
                RemoteTextSpan.self,
                from: data
            )
            #expect(decoded.underline == style)
        }
    }
}
