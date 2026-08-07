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

    // MARK: - removingCharacters(at:)

    @Test
    func removingCharactersDropsOneCharacterFromSpanMiddle() {
        let line = RemoteStyledLine(spans: [RemoteTextSpan(text: "hello")])
        let result = line.removingCharacters(at: [2])
        #expect(result.plainText == "helo")
    }

    @Test
    func removingCharactersDropsAWholeSingleCharacterSpan() {
        let line = RemoteStyledLine(spans: [
            RemoteTextSpan(text: "a", foreground: 0xFF0000),
            RemoteTextSpan(text: "b", foreground: 0x00FF00),
            RemoteTextSpan(text: "c", foreground: 0x0000FF),
        ])
        let result = line.removingCharacters(at: [1])
        #expect(result.plainText == "ac")
        // The now-empty middle span is dropped entirely rather than kept
        // around as a zero-length span.
        #expect(result.spans.count == 2)
        #expect(result.spans.map(\.foreground) == [0xFF0000, 0x0000FF])
    }

    @Test
    func removingCharactersPreservesStyleAcrossMultipleSpans() {
        let line = RemoteStyledLine(spans: [
            RemoteTextSpan(text: "abc", bold: true),
            RemoteTextSpan(text: "def", italic: true),
        ])
        // Removes "c" (last of span 0) and "d" (first of span 1) — a
        // deletion straddling the span boundary.
        let result = line.removingCharacters(at: [2, 3])
        #expect(result.plainText == "abef")
        #expect(result.spans.count == 2)
        #expect(result.spans[0].text == "ab")
        #expect(result.spans[0].bold == true)
        #expect(result.spans[1].text == "ef")
        #expect(result.spans[1].italic == true)
    }

    @Test
    func removingCharactersToleratesOutOfRangeIndices() {
        let line = RemoteStyledLine(spans: [RemoteTextSpan(text: "abc")])
        let result = line.removingCharacters(at: [10])
        #expect(result.plainText == "abc")
    }

    @Test
    func removingCharactersToleratesDuplicateIndices() {
        let line = RemoteStyledLine(spans: [RemoteTextSpan(text: "abc")])
        let result = line.removingCharacters(at: [1, 1])
        #expect(result.plainText == "ac")
    }

    @Test
    func removingCharactersToleratesDescendingIndices() {
        // Offsets are contractually ascending; a descending list is
        // malformed input that must not crash or delete an unintended
        // character — it degrades gracefully instead.
        let line = RemoteStyledLine(spans: [RemoteTextSpan(text: "abc")])
        let result = line.removingCharacters(at: [2, 0])
        #expect(result.plainText.count <= 3)
    }

    @Test
    func removingCharactersWithEmptyOffsetsIsIdentity() {
        let line = RemoteStyledLine(spans: [
            RemoteTextSpan(text: "abc", bold: true),
        ])
        #expect(line.removingCharacters(at: []) == line)
    }

    @Test
    func removingCharactersOffsetsAreCharacterIndicesNotUTF16() {
        // "あ" is one Character but more than one UTF-16 code unit; index 1
        // must remove the second Character ("i"), proving offsets are
        // Character-indexed rather than code-unit-indexed.
        let line = RemoteStyledLine(spans: [RemoteTextSpan(text: "あiう")])
        let result = line.removingCharacters(at: [1])
        #expect(result.plainText == "あう")
    }

    // MARK: - joining(_:)

    @Test
    func joiningMergesAdjacentSpansWithTheSameStyleAcrossLineBoundaries() {
        let lines = [
            RemoteStyledLine(spans: [
                RemoteTextSpan(text: "ab", foreground: 0xFF0000),
            ]),
            RemoteStyledLine(spans: [
                RemoteTextSpan(text: "cd", foreground: 0xFF0000),
            ]),
            RemoteStyledLine(spans: [
                RemoteTextSpan(text: "ef", foreground: 0x00FF00),
            ]),
        ]
        let joined = RemoteStyledLine.joining(lines)
        #expect(joined.plainText == "abcdef")
        // The first two lines share a style and coalesce into one span;
        // the differently-colored third line stays separate.
        #expect(joined.spans.count == 2)
        #expect(joined.spans[0].text == "abcd")
        #expect(joined.spans[0].foreground == 0xFF0000)
        #expect(joined.spans[1].text == "ef")
        #expect(joined.spans[1].foreground == 0x00FF00)
    }

    @Test
    func joiningOfEmptyLinesIsAnEmptyLine() {
        let joined = RemoteStyledLine.joining([])
        #expect(joined.plainText == "")
        #expect(joined.spans.isEmpty)
    }

    @Test
    func joiningDoesNotCoalesceSpansThatDifferOnlyInText() {
        // Two spans with different underline styles must never merge even
        // if every other attribute matches — hasSameStyle checks the full
        // attribute set, not just color.
        let lines = [
            RemoteStyledLine(spans: [
                RemoteTextSpan(text: "a", underline: .single),
            ]),
            RemoteStyledLine(spans: [
                RemoteTextSpan(text: "b", underline: .curly),
            ]),
        ]
        let joined = RemoteStyledLine.joining(lines)
        #expect(joined.spans.count == 2)
    }
}
