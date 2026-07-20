import Foundation

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

    public init(
        text: String,
        foreground: Int? = nil,
        background: Int? = nil,
        bold: Bool = false,
        faint: Bool = false,
        inverse: Bool = false
    ) {
        self.text = text
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.faint = faint
        self.inverse = inverse
    }

    private enum CodingKeys: String, CodingKey {
        case text = "t"
        case foreground = "f"
        case background = "b"
        case bold = "o"
        case faint = "d"
        case inverse = "v"
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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(foreground, forKey: .foreground)
        try container.encodeIfPresent(background, forKey: .background)
        if bold { try container.encode(true, forKey: .bold) }
        if faint { try container.encode(true, forKey: .faint) }
        if inverse { try container.encode(true, forKey: .inverse) }
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
    public var plainText: String {
        spans.map(\.text).joined()
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
