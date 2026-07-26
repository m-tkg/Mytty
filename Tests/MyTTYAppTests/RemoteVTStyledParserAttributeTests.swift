import Testing

@testable import MyTTYApp
import MyTTYRemoteKit

/// Covers the attributes beyond colour/bold/faint/inverse, and the
/// colon-subparameter form they arrive in.
@Suite("Remote VT styled parser attributes")
struct RemoteVTStyledParserAttributeTests {
    private let esc = "\u{1B}"

    private func spans(_ vt: String) -> [RemoteTextSpan] {
        RemoteVTStyledParser.parse(vt).first?.spans ?? []
    }

    @Test("italic is set by SGR 3 and cleared by 23")
    func italic() {
        let result = spans("\(esc)[3mI\(esc)[23mP")
        #expect(result.count == 2)
        #expect(result[0].italic)
        #expect(!result[1].italic)
    }

    @Test("strikethrough is set by SGR 9 and cleared by 29")
    func strikethrough() {
        let result = spans("\(esc)[9mS\(esc)[29mP")
        #expect(result.count == 2)
        #expect(result[0].strikethrough)
        #expect(!result[1].strikethrough)
    }

    @Test("bare SGR 4 is a single underline, 24 clears it")
    func plainUnderline() {
        let result = spans("\(esc)[4mU\(esc)[24mP")
        #expect(result.count == 2)
        #expect(result[0].underline == .single)
        #expect(result[1].underline == .none)
    }

    @Test("SGR 21 is a double underline")
    func doubleUnderline() {
        #expect(spans("\(esc)[21mD")[0].underline == .double)
    }

    @Test("a colon subparameter names the underline style")
    func underlineStyleSubparameter() {
        // The whole point of tracking subparameters: without it the `3` of
        // `4:3` would be read as a separate italic parameter.
        let result = spans("\(esc)[4:3mC")
        #expect(result[0].underline == .curly)
        #expect(!result[0].italic)

        #expect(spans("\(esc)[4:0mN")[0].underline == .none)
        #expect(spans("\(esc)[4:2mD")[0].underline == .double)
        #expect(spans("\(esc)[4:4mO")[0].underline == .dotted)
        #expect(spans("\(esc)[4:5mA")[0].underline == .dashed)
    }

    @Test("an unknown underline subparameter still underlines")
    func unknownUnderlineSubparameter() {
        // The host drew *some* underline; dropping it entirely would lose
        // more than falling back to a plain one.
        #expect(spans("\(esc)[4:9mU")[0].underline == .single)
    }

    @Test("SGR 58 colors the underline apart from the text, 59 clears it")
    func underlineColor() {
        let result = spans("\(esc)[4;58;2;255;0;0mU\(esc)[59mP")
        #expect(result.count == 2)
        #expect(result[0].underlineColor == 0xFF0000)
        #expect(result[1].underlineColor == nil)
    }

    @Test("underline color also parses in the colon form")
    func underlineColorColonForm() {
        let result = spans("\(esc)[4:3;58:2::255:0:0mU")
        #expect(result[0].underline == .curly)
        #expect(result[0].underlineColor == 0xFF0000)
    }

    @Test("truecolor still parses in the semicolon form")
    func truecolorSemicolonForm() {
        let result = spans("\(esc)[38;2;18;52;86mT")
        #expect(result[0].foreground == 0x123456)
    }

    @Test("truecolor parses in the colon form too")
    func truecolorColonForm() {
        // `38:2:r:g:b` must not swallow the parameters that follow it.
        let result = spans("\(esc)[38:2:18:52:86;1mT")
        #expect(result[0].foreground == 0x123456)
        #expect(result[0].bold)
    }

    @Test("SGR 0 clears every attribute at once")
    func resetClearsEverything() {
        let result = spans("\(esc)[1;3;4;9;58;2;255;0;0mA\(esc)[0mB")
        #expect(result.count == 2)
        #expect(result[0].bold)
        #expect(result[0].italic)
        #expect(result[0].underline == .single)
        #expect(result[0].strikethrough)
        #expect(result[0].underlineColor == 0xFF0000)

        #expect(!result[1].bold)
        #expect(!result[1].italic)
        #expect(result[1].underline == .none)
        #expect(!result[1].strikethrough)
        #expect(result[1].underlineColor == nil)
    }

    @Test("a truncated extended color does not run past the parameters")
    func truncatedExtendedColor() {
        // `38;2` with no channels is malformed; the parser must drop it
        // rather than read into whatever follows.
        let result = spans("\(esc)[38;2mX")
        #expect(result.count == 1)
        #expect(result[0].foreground == nil)
        #expect(result[0].text == "X")
    }
}
