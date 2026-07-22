import AppKit
import ImageIO
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Terminal recording")
struct TerminalRecordingTests {
    @Test("limits recordings to sixty seconds at eight frames per second")
    func recordingLimits() {
        #expect(TerminalRecordingConfiguration.maximumDuration == 60)
        #expect(TerminalRecordingConfiguration.framesPerSecond == 8)
        #expect(TerminalRecordingConfiguration.maximumFrameCount == 480)
        #expect(TerminalRecordingConfiguration.maximumPixelDimension == 4_096)
    }

    @Test("formats pressed keys for the optional recording overlay")
    @MainActor
    func keyLabels() throws {
        let shortcut = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift, .command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "G",
            charactersIgnoringModifiers: "g",
            isARepeat: false,
            keyCode: 5
        ))
        let returnKey = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))

        #expect(TerminalKeyLabel.text(for: shortcut) == "⇧⌘G")
        #expect(TerminalKeyLabel.text(for: returnKey) == "Return")
    }

    @Test("positions recorded keys like the live cursor toast")
    @MainActor
    func recordedKeyPosition() {
        let bounds = NSRect(x: 0, y: 0, width: 600, height: 400)
        let cursor = NSRect(x: 280, y: 240, width: 10, height: 20)
        let size = PressedKeyToastLayout.toastSize(
            for: "⌘D",
            maximumWidth: bounds.width - 12
        )
        let expected = PressedKeyToastLayout.frame(
            cursorRect: cursor,
            toastSize: size,
            in: bounds
        )

        let recorded = TerminalFrameCapture.keyLabelFrame(
            keyLabel: "⌘D",
            cursorRect: cursor,
            in: bounds
        )

        #expect(recorded == expected)
        #expect(recorded.maxY == 234)
        #expect(recorded.midX == 285)
    }

    @Test("captures a large pane at native backing resolution")
    @MainActor
    func captureResolution() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_500, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = NSView(
            frame: NSRect(x: 0, y: 0, width: 1_500, height: 700)
        )
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = view
        let backingBounds = view.convertToBacking(view.bounds)

        let image = try TerminalFrameCapture.image(
            from: view,
            keyLabel: nil
        )

        #expect(image.width == Int(backingBounds.width))
        #expect(image.height == Int(backingBounds.height))
    }

    @Test("chooses the GIF destination after capture stops")
    @MainActor
    func deferredDestination() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mytty-recording-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("recording.gif")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = NSView(frame: window.contentView?.bounds ?? .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = view
        let recorder = TerminalGIFRecorder(
            tabID: TabID(),
            surfaceID: TerminalSurfaceID(),
            view: view,
            showPressedKeys: false,
            keyLabelCursorRect: { .zero },
            onLimitReached: {},
            onFailure: { _ in }
        )

        try recorder.start()
        recorder.stopCapturing()

        #expect(!FileManager.default.fileExists(atPath: output.path))

        let result = await withCheckedContinuation { continuation in
            recorder.finish(to: output) { result in
                continuation.resume(returning: result)
            }
        }
        let savedURL = try result.get()

        #expect(savedURL == output)
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test("encodes multiple frames as a looping animated GIF")
    func animatedGIF() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mytty-recording-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("recording.gif")
        let frames = [
            try makeImage(red: 1, green: 0, blue: 0),
            try makeImage(red: 0, green: 0, blue: 1),
        ]

        try AnimatedGIFEncoder().encode(
            frames: frames,
            frameDelay: 0.125,
            to: output
        )

        let source = try #require(CGImageSourceCreateWithURL(
            output as CFURL,
            nil
        ))
        #expect(CGImageSourceGetCount(source) == 2)
        let properties = try #require(
            CGImageSourceCopyProperties(source, nil)
                as? [CFString: Any]
        )
        let gif = try #require(
            properties[kCGImagePropertyGIFDictionary]
                as? [CFString: Any]
        )
        #expect((gif[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue == 0)
    }

    @Test("splits the fade-out duration into per-frame alpha steps")
    func fadeOutAlphas() {
        let fadeOut = TerminalRecordingFadeOut(
            duration: 0.5,
            colorHex: "000000"
        )
        #expect(
            fadeOut.alphas(frameDelay: 0.125) == [0.25, 0.5, 0.75, 1.0]
        )

        let short = TerminalRecordingFadeOut(
            duration: 0.01,
            colorHex: "000000"
        )
        #expect(short.alphas(frameDelay: 0.125) == [1.0])

        let invalid = TerminalRecordingFadeOut(
            duration: 0,
            colorHex: "000000"
        )
        #expect(invalid.alphas(frameDelay: 0.125).isEmpty)
    }

    @Test("parses the fade-out color hex into components")
    func fadeOutColorComponents() {
        let fadeOut = TerminalRecordingFadeOut(
            duration: 1,
            colorHex: "FF8800"
        )
        let components = fadeOut.colorComponents
        #expect(components.red == 1)
        #expect(abs(components.green - CGFloat(0x88) / 255) < 0.001)
        #expect(components.blue == 0)

        let malformed = TerminalRecordingFadeOut(
            duration: 1,
            colorHex: "not-a-color"
        )
        let fallback = malformed.colorComponents
        #expect(fallback.red == 0)
        #expect(fallback.green == 0)
        #expect(fallback.blue == 0)
    }

    @Test("overlays the fade color onto the final frame")
    func fadeOutFrameRendering() throws {
        let base = try makeImage(red: 1, green: 0, blue: 0)
        // DeviceRGB is the display's profile (P3 on modern Macs), so the
        // sRGB red lands on device-dependent component values; compare the
        // fade output against the base pixel instead of literal channels.
        let basePixel = try #require(pixel(of: base))
        let fadeOut = TerminalRecordingFadeOut(
            duration: 1,
            colorHex: "000000"
        )

        let opaque = try TerminalRecordingFadeOutRenderer.image(
            over: base,
            fadeOut: fadeOut,
            alpha: 1
        )
        let opaquePixel = try #require(pixel(of: opaque))
        #expect(opaquePixel.red == 0)
        #expect(opaquePixel.green == 0)
        #expect(opaquePixel.blue == 0)

        let half = try TerminalRecordingFadeOutRenderer.image(
            over: base,
            fadeOut: fadeOut,
            alpha: 0.5
        )
        let halfPixel = try #require(pixel(of: half))
        #expect(abs(Int(halfPixel.red) - Int(basePixel.red) / 2) <= 2)
        #expect(abs(Int(halfPixel.green) - Int(basePixel.green) / 2) <= 2)
        #expect(abs(Int(halfPixel.blue) - Int(basePixel.blue) / 2) <= 2)
    }

    @Test("appends fade-out frames after the recorded frames")
    @MainActor
    func fadeOutAppendsFrames() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mytty-recording-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("recording.gif")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = NSView(frame: window.contentView?.bounds ?? .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.red.cgColor
        window.contentView = view
        let recorder = TerminalGIFRecorder(
            tabID: TabID(),
            surfaceID: TerminalSurfaceID(),
            view: view,
            showPressedKeys: false,
            keyLabelCursorRect: { .zero },
            onLimitReached: {},
            onFailure: { _ in }
        )

        try recorder.start()
        recorder.stopCapturing()

        // 0.25 s at 8 fps adds two fade frames after the captured frame.
        let result = await withCheckedContinuation { continuation in
            recorder.finish(
                to: output,
                fadeOut: TerminalRecordingFadeOut(
                    duration: 0.25,
                    colorHex: "000000"
                )
            ) { result in
                continuation.resume(returning: result)
            }
        }
        _ = try result.get()

        let source = try #require(CGImageSourceCreateWithURL(
            output as CFURL,
            nil
        ))
        #expect(CGImageSourceGetCount(source) == 3)
        let last = try #require(CGImageSourceCreateImageAtIndex(
            source,
            2,
            nil
        ))
        let lastPixel = try #require(pixel(of: last))
        #expect(lastPixel.red <= 2)
        #expect(lastPixel.green <= 2)
        #expect(lastPixel.blue <= 2)
    }

    private func pixel(
        of image: CGImage
    ) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        var data = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (data[0], data[1], data[2])
    }

    private func makeImage(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(
            red: red,
            green: green,
            blue: blue,
            alpha: 1
        ))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try #require(context.makeImage())
    }
}
