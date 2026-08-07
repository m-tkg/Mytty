import Foundation

/// How a span is underlined. Terminals distinguish these (a curly underline
/// is how a compiler or agent marks an error), so a client that collapsed
/// them all to a plain line would lose the distinction the host drew.
public enum RemoteUnderlineStyle: String, Codable, Equatable, Sendable {
    case none = "n"
    case single = "s"
    case double = "d"
    case curly = "c"
    case dotted = "o"
    case dashed = "a"
}

/// A run of characters in a pane that share the same visual style. Colors
/// are already resolved to concrete RGB on the Mac (the terminal palette is
/// applied there), so the phone never needs the theme palette. `nil` colors
/// mean "use the client's default foreground/background". Coding keys are
/// deliberately short because a styled frame carries one of these per color
/// run per line.
public struct RemoteTextSpan: Codable, Equatable, Sendable {
    public var text: String
    /// 0xRRGGBB, or nil for the default foreground.
    public var foreground: Int?
    /// 0xRRGGBB, or nil for the default background.
    public var background: Int?
    public var bold: Bool
    /// Reduced intensity (SGR 2), e.g. terminal dim/faint hint text. The
    /// client renders it as a dimmed foreground, as the Mac does.
    public var faint: Bool
    /// Swap foreground and background at render time, as the terminal does
    /// for reverse-video cells (selected rows, some prompts).
    public var inverse: Bool
    public var italic: Bool
    public var underline: RemoteUnderlineStyle
    /// 0xRRGGBB for an underline coloured apart from the text (SGR 58), or
    /// nil to underline in the foreground colour.
    public var underlineColor: Int?
    public var strikethrough: Bool

    public init(
        text: String,
        foreground: Int? = nil,
        background: Int? = nil,
        bold: Bool = false,
        faint: Bool = false,
        inverse: Bool = false,
        italic: Bool = false,
        underline: RemoteUnderlineStyle = .none,
        underlineColor: Int? = nil,
        strikethrough: Bool = false
    ) {
        self.text = text
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.faint = faint
        self.inverse = inverse
        self.italic = italic
        self.underline = underline
        self.underlineColor = underlineColor
        self.strikethrough = strikethrough
    }

    private enum CodingKeys: String, CodingKey {
        case text = "t"
        case foreground = "f"
        case background = "b"
        case bold = "o"
        case faint = "d"
        case inverse = "v"
        case italic = "i"
        case underline = "u"
        case underlineColor = "uc"
        case strikethrough = "k"
    }

    /// Compares style only, ignoring `text` — used when merging adjacent
    /// spans (e.g. after joining physical lines back into a logical one)
    /// to decide whether they can collapse into a single span.
    func hasSameStyle(as other: RemoteTextSpan) -> Bool {
        foreground == other.foreground
            && background == other.background
            && bold == other.bold
            && faint == other.faint
            && inverse == other.inverse
            && italic == other.italic
            && underline == other.underline
            && underlineColor == other.underlineColor
            && strikethrough == other.strikethrough
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        foreground = try container.decodeIfPresent(Int.self, forKey: .foreground)
        background = try container.decodeIfPresent(Int.self, forKey: .background)
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        faint = try container.decodeIfPresent(Bool.self, forKey: .faint) ?? false
        inverse = try container.decodeIfPresent(Bool.self, forKey: .inverse)
            ?? false
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic)
            ?? false
        underline = try container.decodeIfPresent(
            RemoteUnderlineStyle.self,
            forKey: .underline
        ) ?? .none
        underlineColor = try container.decodeIfPresent(
            Int.self,
            forKey: .underlineColor
        )
        strikethrough = try container.decodeIfPresent(
            Bool.self,
            forKey: .strikethrough
        ) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(foreground, forKey: .foreground)
        try container.encodeIfPresent(background, forKey: .background)
        if bold { try container.encode(true, forKey: .bold) }
        if faint { try container.encode(true, forKey: .faint) }
        if inverse { try container.encode(true, forKey: .inverse) }
        if italic { try container.encode(true, forKey: .italic) }
        if underline != .none {
            try container.encode(underline, forKey: .underline)
        }
        try container.encodeIfPresent(underlineColor, forKey: .underlineColor)
        if strikethrough {
            try container.encode(true, forKey: .strikethrough)
        }
    }
}

/// One visual line of a pane as an ordered list of styled spans. An empty
/// `spans` array is a blank line.
public struct RemoteStyledLine: Codable, Equatable, Sendable {
    public var spans: [RemoteTextSpan]

    public init(spans: [RemoteTextSpan]) {
        self.spans = spans
    }

    /// The line's characters without styling, e.g. for cursor-column math.
    ///
    /// Invariant the host relies on: once `RemoteScrollback` has aligned a
    /// styled line to a plain line, this string is character-for-character
    /// identical to that plain line. Every operation in this file (and in
    /// `RemoteScrollback`) that produces or edits a styled line is written
    /// to preserve that invariant, and callers verify it after every edit
    /// rather than trusting it silently — a mismatch means the styled line
    /// gets dropped in favor of plain text (colour is decoration, text and
    /// cursor position are the contract).
    public var plainText: String {
        spans.map(\.text).joined()
    }

    /// Removes the characters at `offsets` (Character indices into
    /// `plainText`), keeping every span's style intact for the characters
    /// that remain. Used to strip wrap-padding spaces from a styled line
    /// with the same offsets already computed for the corresponding plain
    /// line, so the two stay character-aligned.
    ///
    /// `offsets` must be ascending and free of duplicates; this is the
    /// contract `RemoteScrollback.wrapPaddingIndices` already produces.
    /// Since the input is host-computed rather than wire data, offsets that
    /// violate the contract (out of range, descending, repeated) are
    /// tolerated rather than validated: they're simply skipped instead of
    /// removing the wrong character, so a bug here degrades gracefully
    /// instead of crashing or corrupting unrelated text.
    public func removingCharacters(at offsets: [Int]) -> RemoteStyledLine {
        guard !offsets.isEmpty else { return self }
        var newSpans: [RemoteTextSpan] = []
        var offsetIndex = 0
        var charIndex = 0
        for span in spans {
            var newText = ""
            newText.reserveCapacity(span.text.count)
            for character in span.text {
                // Skip past any offsets that no longer make sense (behind
                // the cursor, i.e. not ascending) so a malformed offset
                // list can't desync the walk or delete the wrong
                // character.
                while offsetIndex < offsets.count,
                    offsets[offsetIndex] < charIndex {
                    offsetIndex += 1
                }
                if offsetIndex < offsets.count, offsets[offsetIndex] == charIndex {
                    offsetIndex += 1
                } else {
                    newText.append(character)
                }
                charIndex += 1
            }
            if !newText.isEmpty {
                var span = span
                span.text = newText
                newSpans.append(span)
            }
        }
        return RemoteStyledLine(spans: newSpans)
    }

    /// Joins several physical (wrap-broken) styled lines into one logical
    /// line, merging adjacent spans that share the same style across the
    /// join boundary so the result doesn't carry more spans on the wire
    /// than the source did.
    public static func joining(_ lines: [RemoteStyledLine]) -> RemoteStyledLine {
        var result: [RemoteTextSpan] = []
        for line in lines {
            for span in line.spans {
                if span.text.isEmpty { continue }
                if var last = result.last, last.hasSameStyle(as: span) {
                    last.text += span.text
                    result[result.count - 1] = last
                } else {
                    result.append(span)
                }
            }
        }
        return RemoteStyledLine(spans: result)
    }

    private enum CodingKeys: String, CodingKey {
        case spans = "s"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spans = try container.decodeIfPresent(
            [RemoteTextSpan].self,
            forKey: .spans
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !spans.isEmpty { try container.encode(spans, forKey: .spans) }
    }
}
