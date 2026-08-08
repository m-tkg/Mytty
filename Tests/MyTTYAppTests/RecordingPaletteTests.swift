import AppKit
import Testing

@testable import MyTTYApp

/// The palette has to shrink terminal output hard and leave photographic
/// content alone, and it decides which by measuring rather than guessing.
@Suite("Recording palette")
struct RecordingPaletteTests {
    @Test("keeps every color when the recording already fits a palette")
    func exactPaletteForFewColors() throws {
        let frame = try Self.render { context, size in
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        }
        let palette = try #require(
            RecordingPaletteBuilder.build(sampling: [frame])
        )

        #expect(palette.colors.count == 2)
        // Two colors in, two colors out, both untouched.
        for color in palette.colors {
            #expect(palette.mapped(color) == color)
        }
    }

    @Test("collapses antialiased terminal text to a small palette")
    @MainActor
    func smallPaletteForTerminalText() throws {
        let frames = try (0..<4).map { step in
            try Self.renderTerminal(step: step)
        }
        let palette = try #require(
            RecordingPaletteBuilder.build(sampling: frames)
        )

        #expect(palette.colors.count <= 64)
        // The background covers most of the frame, so it has to survive as
        // itself: a background that drifts would change every pixel of
        // every frame and undo the inter-frame diffing.
        let background = try #require(
            RecordingPixelBuffer.read(frames[0])?.pixels.first
        )
        #expect(palette.mapped(background & 0x00FF_FFFF) == background & 0x00FF_FFFF)
    }

    /// A pane showing a photograph cannot be described by a handful of
    /// colors, and forcing one on it would be the visible kind of loss.
    @Test("leaves photographic content to a full palette or none at all")
    func photographicContentIsNotForced() throws {
        let frame = try Self.render { context, size in
            for x in stride(from: 0, to: Int(size.width), by: 1) {
                for y in stride(from: 0, to: Int(size.height), by: 1) {
                    context.setFillColor(CGColor(
                        red: CGFloat(x % 256) / 255,
                        green: CGFloat(y % 256) / 255,
                        blue: CGFloat((x * y) % 256) / 255,
                        alpha: 1
                    ))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }

        let palette = RecordingPaletteBuilder.build(sampling: [frame])

        // Either the largest palette or nothing; never one of the small
        // ones that would band a gradient.
        #expect(palette == nil || palette!.colors.count > 64)
    }

    @Test("maps a pixel to the nearest palette entry")
    func mapsToNearestEntry() {
        // 0x00BBGGRR: pure red and pure blue.
        let palette = RecordingPalette(colors: [0x0000_00FF, 0x00FF_0000])

        #expect(palette.mapped(0x0000_00F0) == 0x0000_00FF)
        #expect(palette.mapped(0x00F0_0000) == 0x00FF_0000)
    }

    @Test("samples a spread of frames rather than all of them")
    func samplesASpread() {
        let frames = Array(0..<100)
        let sampled = RecordingPaletteBuilder.sample(frames)

        #expect(sampled.count == RecordingPaletteBuilder.maximumSampledFrames)
        #expect(sampled.first == 0)
        #expect(sampled.last ?? 0 > 80)
        // A short recording is sampled whole.
        #expect(RecordingPaletteBuilder.sample([1, 2, 3]) == [1, 2, 3])
    }

    // MARK: - Fixtures

    private static let size = CGSize(width: 640, height: 420)

    private static func render(
        _ body: (CGContext, CGSize) -> Void
    ) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        body(context, size)
        return try #require(context.makeImage())
    }

    @MainActor
    private static func renderTerminal(step: Int) throws -> CGImage {
        try render { context, size in
            context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(
                cgContext: context,
                flipped: false
            )
            defer { NSGraphicsContext.current = previous }
            let colors: [NSColor] = [
                NSColor(white: 0.85, alpha: 1), .systemGreen, .systemBlue,
                .systemOrange, .systemRed, .systemTeal,
            ]
            for row in 0..<26 {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: colors[(row + step) % colors.count],
                ]
                ("line \(row + step): the quick brown fox" as NSString).draw(
                    at: CGPoint(x: 4, y: size.height - CGFloat(row + 1) * 14),
                    withAttributes: attributes
                )
            }
        }
    }
}
