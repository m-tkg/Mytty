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
