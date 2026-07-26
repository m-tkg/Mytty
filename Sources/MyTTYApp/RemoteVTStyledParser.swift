import Foundation
import MyTTYRemoteKit

/// Parses the replayable VT/ANSI output from `screenVTText()` into styled
/// lines with colors already resolved to RGB, so remote clients render the
/// Mac's exact colors without needing the terminal palette.
///
/// The input begins with the theme palette as OSC 4 sequences
/// (`ESC ] 4 ; index ; rgb:rr/gg/bb ESC \`) followed by screen content that
/// uses SGR (`ESC [ ... m`) for styling. Everything else (other CSI/OSC
/// sequences, carriage returns) is skipped.
enum RemoteVTStyledParser {
    private struct Style: Equatable {
        var foreground: Int?
        var background: Int?
        var bold = false
        var faint = false
        var inverse = false
        var italic = false
        var underline: RemoteUnderlineStyle = .none
        var underlineColor: Int?
        var strikethrough = false
    }

    /// One CSI parameter with its colon-separated subparameters, e.g.
    /// `4:3` (curly underline) or `38:2:0:255:0` (truecolor). Keeping the
    /// two apart matters: flattening them would read the `3` of `4:3` as a
    /// separate "italic" parameter.
    private struct CSIParameter: Equatable {
        var value: Int
        var subparameters: [Int] = []
    }

    static func parse(_ vt: String) -> [RemoteStyledLine] {
        var palette = defaultPalette
        let scalars = Array(vt.unicodeScalars)
        var index = 0
        let count = scalars.count

        var lines: [RemoteStyledLine] = []
        var currentSpans: [RemoteTextSpan] = []
        var runText = ""
        var style = Style()
        var runStyle = Style()

        func flushRun() {
            guard !runText.isEmpty else { return }
            currentSpans.append(
                RemoteTextSpan(
                    text: runText,
                    foreground: runStyle.foreground,
                    background: runStyle.background,
                    bold: runStyle.bold,
                    faint: runStyle.faint,
                    inverse: runStyle.inverse,
                    italic: runStyle.italic,
                    underline: runStyle.underline,
                    underlineColor: runStyle.underlineColor,
                    strikethrough: runStyle.strikethrough
                )
            )
            runText = ""
        }

        func endLine() {
            flushRun()
            lines.append(RemoteStyledLine(spans: currentSpans))
            currentSpans = []
        }

        func append(_ scalar: Unicode.Scalar) {
            if runText.isEmpty {
                runStyle = style
            } else if style != runStyle {
                flushRun()
                runStyle = style
            }
            runText.unicodeScalars.append(scalar)
        }

        while index < count {
            let scalar = scalars[index]
            switch scalar.value {
            case 0x1B: // ESC
                index += 1
                guard index < count else { break }
                let next = scalars[index]
                if next == "[" {
                    index += 1
                    let (params, final) = readCSI(scalars, from: &index)
                    if final == "m" {
                        applySGR(params, to: &style, palette: palette)
                    }
                } else if next == "]" {
                    index += 1
                    let body = readOSC(scalars, from: &index)
                    applyOSC(body, to: &palette)
                } else {
                    // Two-character escape (e.g. ST's "ESC \"); skip it.
                    index += 1
                }
            case 0x0A: // \n
                endLine()
                index += 1
            case 0x0D: // \r
                index += 1
            case 0x09: // tab, keep for spacing
                append(scalar)
                index += 1
            case 0..<0x20:
                index += 1 // drop other C0 controls
            default:
                append(scalar)
                index += 1
            }
        }

        flushRun()
        if !currentSpans.isEmpty {
            lines.append(RemoteStyledLine(spans: currentSpans))
        }
        return lines
    }

    /// Reads a CSI sequence body after `ESC [`, returning its numeric
    /// parameters and final byte. Leaves `index` just past the final byte.
    private static func readCSI(
        _ scalars: [Unicode.Scalar],
        from index: inout Int
    ) -> (params: [CSIParameter], final: Unicode.Scalar?) {
        var digits = ""
        var params: [CSIParameter] = []
        var final: Unicode.Scalar?

        func commit(asSubparameter: Bool) {
            let value = Int(digits) ?? 0
            digits = ""
            if asSubparameter, !params.isEmpty {
                params[params.count - 1].subparameters.append(value)
            } else {
                params.append(CSIParameter(value: value))
            }
        }

        // Whether the digits being accumulated follow a colon, and so
        // belong to the parameter before them rather than standing alone.
        var pendingIsSubparameter = false

        while index < scalars.count {
            let scalar = scalars[index]
            index += 1
            switch scalar.value {
            case 0x30...0x39: // 0-9
                digits.unicodeScalars.append(scalar)
            case 0x3B: // ; starts a new parameter
                commit(asSubparameter: pendingIsSubparameter)
                pendingIsSubparameter = false
            case 0x3A: // : starts a subparameter of the current one
                commit(asSubparameter: pendingIsSubparameter)
                pendingIsSubparameter = true
            case 0x40...0x7E: // final byte
                final = scalar
                if !digits.isEmpty || !params.isEmpty {
                    commit(asSubparameter: pendingIsSubparameter)
                }
                return (params, final)
            default:
                break // intermediate bytes, ignore
            }
        }
        return (params, final)
    }

    /// Reads an OSC body after `ESC ]` up to its terminator (`ESC \` or
    /// BEL), returning the body without the terminator.
    private static func readOSC(
        _ scalars: [Unicode.Scalar],
        from index: inout Int
    ) -> String {
        var body = ""
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x07 { // BEL
                index += 1
                break
            }
            if scalar.value == 0x1B { // possible ST: ESC \
                if index + 1 < scalars.count, scalars[index + 1] == "\\" {
                    index += 2
                    break
                }
                index += 1
                break
            }
            body.unicodeScalars.append(scalar)
            index += 1
        }
        return body
    }

    /// Applies an OSC 4 palette definition (`4;index;rgb:rr/gg/bb`).
    private static func applyOSC(_ body: String, to palette: inout [Int: Int]) {
        let parts = body.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "4",
              let index = Int(parts[1]),
              (0...255).contains(index)
        else { return }
        let spec = parts[2...].joined(separator: ";")
        guard let rgb = parseRGBSpec(spec) else { return }
        palette[index] = rgb
    }

    /// Parses `rgb:rr/gg/bb` (two hex digits per channel) into 0xRRGGBB.
    private static func parseRGBSpec(_ spec: String) -> Int? {
        guard spec.hasPrefix("rgb:") else { return nil }
        let channels = spec.dropFirst(4).split(separator: "/")
        guard channels.count == 3,
              let r = UInt8(channels[0].prefix(2), radix: 16),
              let g = UInt8(channels[1].prefix(2), radix: 16),
              let b = UInt8(channels[2].prefix(2), radix: 16)
        else { return nil }
        return (Int(r) << 16) | (Int(g) << 8) | Int(b)
    }

    private static func applySGR(
        _ params: [CSIParameter],
        to style: inout Style,
        palette: [Int: Int]
    ) {
        guard !params.isEmpty else {
            style = Style()
            return
        }
        var i = 0
        while i < params.count {
            let parameter = params[i]
            switch parameter.value {
            case 0:
                style = Style()
            case 1:
                style.bold = true
            case 2:
                style.faint = true
            case 22:
                style.bold = false
                style.faint = false
            case 3:
                style.italic = true
            case 23:
                style.italic = false
            case 4:
                style.underline = underlineStyle(for: parameter)
            case 21:
                style.underline = .double
            case 24:
                style.underline = .none
            case 9:
                style.strikethrough = true
            case 29:
                style.strikethrough = false
            case 7:
                style.inverse = true
            case 27:
                style.inverse = false
            case 30...37:
                style.foreground = palette[parameter.value - 30]
            case 90...97:
                style.foreground = palette[parameter.value - 90 + 8]
            case 39:
                style.foreground = nil
            case 40...47:
                style.background = palette[parameter.value - 40]
            case 100...107:
                style.background = palette[parameter.value - 100 + 8]
            case 49:
                style.background = nil
            case 38, 48, 58:
                let color = readExtendedColor(
                    params,
                    from: &i,
                    palette: palette
                )
                switch parameter.value {
                case 38: style.foreground = color
                case 48: style.background = color
                default: style.underlineColor = color
                }
            case 59:
                style.underlineColor = nil
            default:
                break
            }
            i += 1
        }
    }

    /// `4` alone is a single underline; `4:n` names the style, with `4:0`
    /// meaning none. An unrecognized subparameter falls back to a single
    /// underline rather than dropping the attribute — the host did draw
    /// *some* underline there.
    private static func underlineStyle(
        for parameter: CSIParameter
    ) -> RemoteUnderlineStyle {
        guard let sub = parameter.subparameters.first else { return .single }
        switch sub {
        case 0: return .none
        case 1: return .single
        case 2: return .double
        case 3: return .curly
        case 4: return .dotted
        case 5: return .dashed
        default: return .single
        }
    }

    /// Reads a `38;5;n` (indexed) or `38;2;r;g;b` (truecolor) color starting
    /// at `params[i]` (the `5` or `2` selector). Advances `i` past the color
    /// arguments and returns the resolved 0xRRGGBB, or nil for a malformed
    /// sequence.
    private static func readExtendedColor(
        _ params: [CSIParameter],
        from i: inout Int,
        palette: [Int: Int]
    ) -> Int? {
        // Colon form: the selector and channels are subparameters of this
        // parameter (`38:2:r:g:b`), so nothing after it is consumed.
        let subparameters = params[i].subparameters
        if !subparameters.isEmpty {
            return color(from: subparameters, palette: palette)
        }
        // Semicolon form: the selector and channels are the parameters
        // that follow (`38;2;r;g;b`).
        let following = params[(i + 1)...].map(\.value)
        guard let selector = following.first else { return nil }
        let consumed = selector == 5 ? 2 : (selector == 2 ? 4 : 0)
        guard consumed > 0 else { return nil }
        guard following.count >= consumed else {
            i = params.count
            return nil
        }
        i += consumed
        return color(from: Array(following.prefix(consumed)), palette: palette)
    }

    /// Resolves `[5, index]` or `[2, r, g, b]` into 0xRRGGBB.
    ///
    /// The colon form of a truecolor sequence may carry a colour-space id
    /// between the selector and the channels (`38:2::r:g:b`, usually left
    /// empty), so the channels are taken from the end rather than from a
    /// fixed offset.
    private static func color(
        from arguments: [Int],
        palette: [Int: Int]
    ) -> Int? {
        switch arguments.first {
        case 5:
            guard arguments.count >= 2 else { return nil }
            let index = arguments[1]
            return palette[index] ?? xterm256(index)
        case 2:
            guard arguments.count >= 4 else { return nil }
            let channels = arguments.suffix(3)
            let r = channels[channels.startIndex] & 0xFF
            let g = channels[channels.startIndex + 1] & 0xFF
            let b = channels[channels.startIndex + 2] & 0xFF
            return (r << 16) | (g << 8) | b
        default:
            return nil
        }
    }

    /// Fallback palette used only if OSC 4 didn't define an index: the
    /// standard xterm 16 colors plus the computed 6x6x6 cube and grayscale
    /// ramp.
    private static let defaultPalette: [Int: Int] = {
        var palette: [Int: Int] = [:]
        for index in 0...255 {
            palette[index] = xterm256(index)
        }
        return palette
    }()

    private static func xterm256(_ index: Int) -> Int {
        let base: [Int] = [
            0x000000, 0x800000, 0x008000, 0x808000,
            0x000080, 0x800080, 0x008080, 0xC0C0C0,
            0x808080, 0xFF0000, 0x00FF00, 0xFFFF00,
            0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
        ]
        if (0...15).contains(index) { return base[index] }
        if (16...231).contains(index) {
            let value = index - 16
            let levels = [0, 95, 135, 175, 215, 255]
            let r = levels[(value / 36) % 6]
            let g = levels[(value / 6) % 6]
            let b = levels[value % 6]
            return (r << 16) | (g << 8) | b
        }
        let gray = 8 + (index - 232) * 10
        return (gray << 16) | (gray << 8) | gray
    }
}
