import Testing

@testable import MyTTYApp
import MyTTYRemoteKit

@Suite("Remote VT styled parser")
struct RemoteVTStyledParserTests {
    private let esc = "\u{1B}"

    @Test("resolves palette colors from the OSC 4 prefix")
    func palettePrefixResolvesColors() {
        let vt = "\(esc)]4;1;rgb:cc/66/66\(esc)\\"
            + "\(esc)[31mRED\(esc)[0mX"
        let lines = RemoteVTStyledParser.parse(vt)

        #expect(lines.count == 1)
        let spans = lines[0].spans
        #expect(spans.count == 2)
        #expect(spans[0].text == "RED")
        #expect(spans[0].foreground == 0xCC6666)
        #expect(spans[1].text == "X")
        #expect(spans[1].foreground == nil)
    }

    @Test("parses truecolor foreground and background")
    func truecolorSpans() {
        let vt = "\(esc)[38;2;10;20;30m\(esc)[48;2;40;50;60mAB\(esc)[0m"
        let spans = RemoteVTStyledParser.parse(vt)[0].spans

        #expect(spans.count == 1)
        #expect(spans[0].foreground == 0x0A141E)
        #expect(spans[0].background == 0x28323C)
    }

    @Test("tracks bold and inverse and resets on SGR 0")
    func boldInverseReset() {
        let vt = "\(esc)[1mB\(esc)[7mI\(esc)[0mP"
        let spans = RemoteVTStyledParser.parse(vt)[0].spans

        #expect(spans.count == 3)
        #expect(spans[0].text == "B")
        #expect(spans[0].bold)
        #expect(!spans[0].inverse)
        #expect(spans[1].text == "I")
        #expect(spans[1].bold)
        #expect(spans[1].inverse)
        #expect(spans[2].text == "P")
        #expect(!spans[2].bold)
        #expect(!spans[2].inverse)
    }

    @Test("tracks faint (dim) text and clears it with SGR 22")
    func faintText() {
        // Faint text alone, then faint + a color, then normal.
        let vt = "\(esc)[2mDIM\(esc)[38;5;5mFC\(esc)[22mNORM\(esc)[0m"
        let spans = RemoteVTStyledParser.parse(vt)[0].spans

        #expect(spans.count == 3)
        #expect(spans[0].text == "DIM")
        #expect(spans[0].faint)
        #expect(spans[0].foreground == nil)
        #expect(spans[1].text == "FC")
        #expect(spans[1].faint)
        #expect(spans[1].foreground != nil)
        #expect(spans[2].text == "NORM")
        #expect(!spans[2].faint)
    }

    @Test("resolves 256-color indices via the xterm cube fallback")
    func indexed256Fallback() {
        // 208 -> orange in the 6x6x6 cube (ff/87/00) without an OSC prefix.
        let vt = "\(esc)[38;5;208mO\(esc)[0m"
        let spans = RemoteVTStyledParser.parse(vt)[0].spans

        #expect(spans[0].foreground == 0xFF8700)
    }

    @Test("splits lines on newlines and skips carriage returns")
    func lineSplitting() {
        let vt = "one\r\n\(esc)[32mtwo\(esc)[0m"
        let lines = RemoteVTStyledParser.parse(vt)

        #expect(lines.count == 2)
        #expect(lines[0].plainText == "one")
        #expect(lines[1].plainText == "two")
        #expect(lines[1].spans[0].foreground == 0x008000)
    }

    @Test("ignores unrelated OSC and CSI sequences")
    func ignoresOtherSequences() {
        let vt = "\(esc)]0;window title\(esc)\\"
            + "\(esc)[2Kkept\(esc)[0m"
        let lines = RemoteVTStyledParser.parse(vt)

        #expect(lines.count == 1)
        #expect(lines[0].plainText == "kept")
    }
}
