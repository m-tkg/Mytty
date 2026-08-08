import AppKit
import ImageIO
import MyTTYCore
import UniformTypeIdentifiers

enum TerminalRecordingConfiguration {
    static let maximumDuration: TimeInterval = 60
    static let framesPerSecond = 8
    /// How many times the recording samples the pane, not how many frames
    /// the GIF ends up with: consecutive samples that look identical are
    /// folded into one frame whose delay covers all of them.
    static let maximumCaptureCount = Int(maximumDuration)
        * framesPerSecond
    static let frameDelay = 1 / Double(framesPerSecond)
    /// Longest run of identical samples one frame may absorb (5s). GIF's
    /// delay field could hold far more, but a frame that sits still for
    /// minutes scrubs badly and some viewers clamp very long delays.
    static let maximumFrameRunTicks = 40
    static let maximumPixelDimension = 4_096
    static let keyLabelDuration: TimeInterval = 1.2
}

/// Turns runs of identical samples into GIF delays.
///
/// GIF stores delays in hundredths of a second, and the 0.125s sampling
/// interval does not land on that grid. Rounding each frame on its own
/// would drift — 8 frames of 0.125s would become 8 × 13cs = 1.04s. So the
/// rounding is applied to the *cumulative* time and the delays are the
/// differences, which alternates 13, 12, 13, 12 … and keeps the total
/// exact.
enum RecordingFrameTiming {
    static func delaysCentiseconds(
        runs: [Int],
        frameDelay: TimeInterval
    ) -> [Int] {
        var delays: [Int] = []
        delays.reserveCapacity(runs.count)
        var ticks = 0
        var elapsed = 0
        for run in runs {
            ticks += max(1, run)
            let boundary = Int((Double(ticks) * frameDelay * 100).rounded())
            // A zero delay is read as "as fast as possible" by some
            // viewers and as 10cs by others; never emit one.
            delays.append(max(1, boundary - elapsed))
            elapsed = boundary
        }
        return delays
    }
}

enum TerminalRecordingError: Error, Sendable, CustomStringConvertible {
    case terminalPaneRequired
    case unableToCapture
    case unableToCreateTemporaryDirectory
    case unableToWriteFrame
    case noFrames
    case unableToEncode
    case unableToSave

    var description: String {
        switch self {
        case .terminalPaneRequired:
            "Select a terminal pane before starting a recording."
        case .unableToCapture:
            "The terminal pane could not be captured."
        case .unableToCreateTemporaryDirectory:
            "The recording workspace could not be created."
        case .unableToWriteFrame:
            "A recording frame could not be saved."
        case .noFrames:
            "The recording did not contain any frames."
        case .unableToEncode:
            "The animated GIF could not be encoded."
        case .unableToSave:
            "The animated GIF could not be saved."
        }
    }
}

enum TerminalKeyLabel {
    @MainActor
    static func text(for event: NSEvent) -> String? {
        guard event.type == .keyDown else { return nil }
        let modifiers = event.modifierFlags.intersection(
            [.control, .option, .shift, .command]
        )
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += keyName(for: event)
        return result.isEmpty ? nil : result
    }

    @MainActor
    private static func keyName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36, 76: "Return"
        case 48: "Tab"
        case 49: "Space"
        case 51, 117: "Delete"
        case 53: "Esc"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default:
            event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .controlCharacters)
                .uppercased() ?? ""
        }
    }
}

/// Fade-to-color applied after the last captured frame so a looping GIF
/// visibly ends before it restarts.
struct TerminalRecordingFadeOut: Equatable, Sendable {
    var duration: TimeInterval
    var colorHex: String

    /// The per-frame overlay opacities, easing (smoothstep) up to fully
    /// opaque so the ramp starts and ends gradually instead of linearly.
    /// Empty when the duration or frame delay is not positive; otherwise at
    /// least one frame, even for durations shorter than a single frame.
    func alphas(frameDelay: TimeInterval) -> [Double] {
        guard duration > 0, frameDelay > 0 else { return [] }
        let count = max(1, Int((duration / frameDelay).rounded()))
        return (1...count).map { step in
            let t = Double(step) / Double(count)
            return t * t * (3 - 2 * t)  // smoothstep
        }
    }

    /// `colorHex` parsed as `RRGGBB`; falls back to black when malformed,
    /// because by the time the fade renders the recording frames are already
    /// on disk and failing the save over a color would be worse.
    var colorComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        guard let hex = RecordingFadeOut.normalizedColorHex(colorHex),
              let value = UInt32(hex, radix: 16)
        else { return (0, 0, 0) }
        return (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }
}

enum TerminalRecordingFadeOutRenderer {
    static func image(
        over base: CGImage,
        fadeOut: TerminalRecordingFadeOut,
        alpha: Double
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: base.width,
            height: base.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw TerminalRecordingError.unableToEncode }
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: base.width,
            height: base.height
        )
        context.draw(base, in: bounds)
        let color = fadeOut.colorComponents
        context.setFillColor(CGColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: alpha
        ))
        context.fill(bounds)
        guard let image = context.makeImage() else {
            throw TerminalRecordingError.unableToEncode
        }
        return image
    }

    /// Renders the fade frames over `lastFrameURL` and writes them as PNGs
    /// next to the captured frames, returning their URLs in playback order.
    static func frames(
        after lastFrameURL: URL,
        fadeOut: TerminalRecordingFadeOut,
        frameDelay: TimeInterval,
        in directory: URL
    ) throws -> [URL] {
        let alphas = fadeOut.alphas(frameDelay: frameDelay)
        guard !alphas.isEmpty else { return [] }
        guard let source = CGImageSourceCreateWithURL(
            lastFrameURL as CFURL,
            nil
        ), let base = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TerminalRecordingError.unableToEncode
        }
        return try alphas.enumerated().map { index, alpha in
            let frame = try image(over: base, fadeOut: fadeOut, alpha: alpha)
            let url = directory.appendingPathComponent(
                String(format: "fade-%04d.png", index)
            )
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else { throw TerminalRecordingError.unableToWriteFrame }
            CGImageDestinationAddImage(destination, frame, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw TerminalRecordingError.unableToWriteFrame
            }
            return url
        }
    }
}

struct AnimatedGIFEncoder: Sendable {
    func encode(
        frames: [CGImage],
        frameDelay: TimeInterval,
        to outputURL: URL
    ) throws {
        let delay = max(1, Int((frameDelay * 100).rounded()))
        try encode(
            frameCount: frames.count,
            delayCentisecondsAt: { _ in delay },
            outputURL: outputURL,
            imageAt: { frames[$0] }
        )
    }

    /// Per-frame delays, in hundredths of a second: a frame that stood in
    /// for several identical samples carries all of their time.
    ///
    /// `palette`, when present, is applied to every frame on the way in so
    /// they share one set of colors — see `RecordingPalette`.
    func encode(
        frameURLs: [URL],
        delaysCentiseconds: [Int],
        palette: RecordingPalette? = nil,
        paletteFrameCount: Int? = nil,
        to outputURL: URL
    ) throws {
        precondition(frameURLs.count == delaysCentiseconds.count)
        try encode(
            frameCount: frameURLs.count,
            delayCentisecondsAt: { delaysCentiseconds[$0] },
            outputURL: outputURL,
            imageAt: { index in
                guard let source = CGImageSourceCreateWithURL(
                    frameURLs[index] as CFURL,
                    nil
                ), let image = CGImageSourceCreateImageAtIndex(
                    source,
                    0,
                    nil
                ) else {
                    throw TerminalRecordingError.unableToEncode
                }
                guard let palette,
                      index < (paletteFrameCount ?? frameURLs.count)
                else { return image }
                return RecordingPixelBuffer.mapped(image, through: palette)
            }
        )
    }

    private func encode(
        frameCount: Int,
        delayCentisecondsAt: (Int) -> Int,
        outputURL: URL,
        imageAt: (Int) throws -> CGImage
    ) throws {
        guard frameCount > 0 else { throw TerminalRecordingError.noFrames }
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else { throw TerminalRecordingError.unableToEncode }

        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0,
                ],
            ] as CFDictionary
        )
        for index in 0..<frameCount {
            // Both keys carry the same value: readers disagree about which
            // one wins, and a viewer must never see two different delays
            // for one frame.
            let delay = Double(delayCentisecondsAt(index)) / 100
            let properties = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                ],
            ] as CFDictionary
            CGImageDestinationAddImage(
                destination,
                try imageAt(index),
                properties
            )
        }
        guard CGImageDestinationFinalize(destination) else {
            throw TerminalRecordingError.unableToEncode
        }
    }
}

@MainActor
enum TerminalFrameCapture {
    /// The pane's pixels, before the key label is composited on top.
    /// Split out from `image(from:...)` so the recorder can compare one
    /// sample against the last without paying for the composite and the
    /// PNG encode first.
    static func representation(of view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        guard view.bounds.width >= 1,
              view.bounds.height >= 1,
              let representation = view.bitmapImageRepForCachingDisplay(
                  in: view.bounds
              )
        else { throw TerminalRecordingError.unableToCapture }
        view.cacheDisplay(in: view.bounds, to: representation)
        return representation
    }

    static func image(
        from view: NSView,
        keyLabel: String?,
        keyLabelCursorRect: NSRect? = nil
    ) throws -> CGImage {
        try image(
            from: try representation(of: view),
            pointSize: view.bounds.size,
            keyLabel: keyLabel,
            keyLabelCursorRect: keyLabelCursorRect
        )
    }

    static func image(
        from representation: NSBitmapImageRep,
        pointSize: CGSize,
        keyLabel: String?,
        keyLabelCursorRect: NSRect? = nil
    ) throws -> CGImage {
        guard let source = representation.cgImage else {
            throw TerminalRecordingError.unableToCapture
        }
        let bounds = CGRect(origin: .zero, size: pointSize)

        let size = targetPixelSize(
            source: source,
            pointSize: pointSize
        )
        let hasKeyLabel = keyLabel?.isEmpty == false
            && keyLabelCursorRect != nil
        let needsResampling = source.width != size.width
            || source.height != size.height
        guard needsResampling || hasKeyLabel else { return source }
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw TerminalRecordingError.unableToCapture }
        context.interpolationQuality = source.width == size.width
            && source.height == size.height ? .none : .high
        context.draw(
            source,
            in: CGRect(x: 0, y: 0, width: size.width, height: size.height)
        )
        if let keyLabel, !keyLabel.isEmpty, let keyLabelCursorRect {
            let drawingScale = min(
                CGFloat(size.width) / bounds.width,
                CGFloat(size.height) / bounds.height
            )
            let frame = keyLabelFrame(
                keyLabel: keyLabel,
                cursorRect: keyLabelCursorRect,
                in: bounds
            )
            draw(
                keyLabel: keyLabel,
                in: context,
                frame: frame,
                bounds: bounds,
                scale: drawingScale
            )
        }
        guard let image = context.makeImage() else {
            throw TerminalRecordingError.unableToCapture
        }
        return image
    }

    static func keyLabelFrame(
        keyLabel: String,
        cursorRect: NSRect,
        in bounds: NSRect
    ) -> NSRect {
        let size = PressedKeyToastLayout.toastSize(
            for: keyLabel,
            maximumWidth: max(0, bounds.width - 12)
        )
        return PressedKeyToastLayout.frame(
            cursorRect: cursorRect,
            toastSize: size,
            in: bounds
        )
    }

    /// The size a captured frame is written at.
    ///
    /// One point per pixel, rather than the Retina backing resolution the
    /// pane draws at. GIF pays for resolution twice over — every changed
    /// pixel is encoded, and a 256-color palette compresses antialiased
    /// text poorly — so a 2x recording of a scrolling colored log measured
    /// 4.0MB against 1.8MB for the same five seconds at 1x. Nothing else
    /// came close: ImageIO already writes unchanged frames as inter-frame
    /// diffs, and a shared 256-color palette without dithering was worth
    /// under 10%.
    private static func targetPixelSize(
        source: CGImage,
        pointSize: CGSize
    ) -> (width: Int, height: Int) {
        let largestPointDimension = max(pointSize.width, pointSize.height)
        let maximumIntegralScale = max(
            1,
            floor(
                CGFloat(
                    TerminalRecordingConfiguration.maximumPixelDimension
                ) / largestPointDimension
            )
        )
        let sourceScale = min(
            CGFloat(source.width) / pointSize.width,
            CGFloat(source.height) / pointSize.height
        )
        // A pane wider than the 4096px ceiling is still clamped below 1x.
        let targetScale = min(sourceScale, maximumIntegralScale, 1)
        guard targetScale < sourceScale else {
            return (source.width, source.height)
        }
        return (
            max(1, Int((pointSize.width * targetScale).rounded(.up))),
            max(1, Int((pointSize.height * targetScale).rounded(.up)))
        )
    }

    private static func draw(
        keyLabel: String,
        in context: CGContext,
        frame: NSRect,
        bounds: NSRect,
        scale: CGFloat
    ) {
        let font = PressedKeyToastLayout.font(scale: scale)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let textSize = (keyLabel as NSString).size(withAttributes: attributes)
        let rect = CGRect(
            x: (frame.minX - bounds.minX) * scale,
            y: (frame.minY - bounds.minY) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
        guard rect.width > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(
            cgContext: context,
            flipped: false
        )
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(
            roundedRect: rect,
            xRadius: PressedKeyToastLayout.cornerRadius * scale,
            yRadius: PressedKeyToastLayout.cornerRadius * scale
        ).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5 * scale, dy: 0.5 * scale),
            xRadius: PressedKeyToastLayout.cornerRadius * scale,
            yRadius: PressedKeyToastLayout.cornerRadius * scale
        )
        border.lineWidth = scale
        border.stroke()
        (keyLabel as NSString).draw(
            at: CGPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2
            ),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}

@MainActor
final class TerminalGIFRecorder: NSObject {
    let tabID: TabID
    let surfaceID: TerminalSurfaceID

    private weak var view: NSView?
    private let onLimitReached: () -> Void
    private let onFailure: (TerminalRecordingError) -> Void
    private let keyLabelCursorRect: () -> NSRect?
    private var showPressedKeys: Bool
    private var timer: Timer?
    private var temporaryDirectory: URL?

    /// One encoded frame and how many capture ticks it stands for.
    private struct RecordedFrame {
        let url: URL
        var ticks: Int
    }

    /// The last sample's raw pixels, kept so the next one can be rejected
    /// with a `memcmp` instead of a hash: at ~17MB a frame the compare
    /// costs 1-2ms while hashing the same bytes costs ten times that, and
    /// a match here skips the PNG encode entirely — so deduplicating makes
    /// the capture tick cheaper, not dearer.
    private struct FrameSignature {
        var bytes: [UInt8]
        var width: Int
        var height: Int
        var bytesPerRow: Int
        /// The key label lives only in the composited image, so it is
        /// compared as state: same pixels *and* same label means the
        /// composite would have been identical too.
        var keyLabel: String?
        var keyLabelCursorRect: NSRect?
    }

    private var frames: [RecordedFrame] = []
    private var captureCount = 0
    private var previousSignature: FrameSignature?
    private var latestKeyLabel: (
        text: String,
        date: Date,
        cursorRect: NSRect
    )?
    private var startedAt: Date?
    private var isActive = false

    init(
        tabID: TabID,
        surfaceID: TerminalSurfaceID,
        view: NSView,
        showPressedKeys: Bool,
        keyLabelCursorRect: @escaping () -> NSRect?,
        onLimitReached: @escaping () -> Void,
        onFailure: @escaping (TerminalRecordingError) -> Void
    ) {
        self.tabID = tabID
        self.surfaceID = surfaceID
        self.view = view
        self.showPressedKeys = showPressedKeys
        self.keyLabelCursorRect = keyLabelCursorRect
        self.onLimitReached = onLimitReached
        self.onFailure = onFailure
    }

    func start() throws {
        guard !isActive else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "com.m-tkg.mytty/recordings/\(UUID().uuidString)",
                isDirectory: true
            )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw TerminalRecordingError.unableToCreateTemporaryDirectory
        }
        temporaryDirectory = directory
        startedAt = Date()
        isActive = true
        do {
            try captureFrame()
        } catch {
            cancel()
            throw error
        }

        let timer = Timer(
            timeInterval: TerminalRecordingConfiguration.frameDelay,
            target: self,
            selector: #selector(captureTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.015
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func updateShowPressedKeys(_ showPressedKeys: Bool) {
        self.showPressedKeys = showPressedKeys
        if !showPressedKeys {
            latestKeyLabel = nil
        }
    }

    func noteKey(_ event: NSEvent) {
        guard isActive, showPressedKeys,
              let text = TerminalKeyLabel.text(for: event),
              let cursorRect = keyLabelCursorRect()
        else { return }
        latestKeyLabel = (text, Date(), cursorRect)
    }

    func stopCapturing() {
        guard isActive else { return }
        isActive = false
        startedAt = nil
        timer?.invalidate()
        timer = nil
    }

    func finish(
        to outputURL: URL,
        fadeOut: TerminalRecordingFadeOut? = nil,
        completion: @escaping @MainActor (
            Result<URL, TerminalRecordingError>
        ) -> Void
    ) {
        stopCapturing()
        let recorded = frames
        let directory = temporaryDirectory
        frames.removeAll()
        previousSignature = nil
        temporaryDirectory = nil

        Task {
            let result = await Task.detached(priority: .utility) {
                () -> Result<URL, TerminalRecordingError> in
                guard !recorded.isEmpty else { return .failure(.noFrames) }
                guard let directory else {
                    return .failure(.unableToCreateTemporaryDirectory)
                }
                var allFrames = recorded.map(\.url)
                var runs = recorded.map(\.ticks)
                if let fadeOut, let lastFrame = allFrames.last {
                    // A failed fade must not lose the recording itself.
                    let fadeFrames = try? TerminalRecordingFadeOutRenderer
                        .frames(
                            after: lastFrame,
                            fadeOut: fadeOut,
                            frameDelay:
                                TerminalRecordingConfiguration.frameDelay,
                            in: directory
                        )
                    allFrames.append(contentsOf: fadeFrames ?? [])
                    // Every fade frame is its own tick. They go through the
                    // same cumulative rounding as the captured ones so the
                    // fade lasts exactly as long as it was configured to.
                    runs.append(contentsOf: Array(
                        repeating: 1,
                        count: fadeFrames?.count ?? 0
                    ))
                }
                // Built from the captured frames only: the fade blends
                // toward a color that appears nowhere else, and letting it
                // pull the palette would cost the recording itself.
                let palette = RecordingPaletteBuilder.build(
                    samplingFramesAt: recorded.map(\.url)
                )
                let encoded = directory.appendingPathComponent("recording.gif")
                do {
                    try AnimatedGIFEncoder().encode(
                        frameURLs: allFrames,
                        delaysCentiseconds: RecordingFrameTiming
                            .delaysCentiseconds(
                                runs: runs,
                                frameDelay: TerminalRecordingConfiguration
                                    .frameDelay
                            ),
                        palette: palette,
                        // Fade frames keep their own colors: they are
                        // blends toward a color the captured frames never
                        // contain, and a palette built from those frames
                        // would band the one part of the recording whose
                        // whole point is a smooth ramp.
                        paletteFrameCount: recorded.count,
                        to: encoded
                    )
                    let data = try Data(contentsOf: encoded, options: .mappedIfSafe)
                    try data.write(to: outputURL, options: .atomic)
                    try? FileManager.default.removeItem(at: directory)
                    return .success(outputURL)
                } catch let error as TerminalRecordingError {
                    try? FileManager.default.removeItem(at: directory)
                    return .failure(error)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    return .failure(.unableToSave)
                }
            }.value
            completion(result)
        }
    }

    func cancel() {
        isActive = false
        startedAt = nil
        timer?.invalidate()
        timer = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        frames.removeAll()
        captureCount = 0
        previousSignature = nil
    }

    @objc private func captureTimerFired(_ timer: Timer) {
        captureTick()
    }

    /// One capture tick. Separate from the timer callback so tests can
    /// drive a recording without waiting on the run loop.
    func captureTick() {
        let elapsed = startedAt.map { Date().timeIntervalSince($0) }
            ?? TerminalRecordingConfiguration.maximumDuration
        guard elapsed < TerminalRecordingConfiguration.maximumDuration,
              captureCount
                < TerminalRecordingConfiguration.maximumCaptureCount
        else {
            onLimitReached()
            return
        }
        do {
            try captureFrame()
        } catch let error as TerminalRecordingError {
            cancel()
            onFailure(error)
        } catch {
            cancel()
            onFailure(.unableToCapture)
        }
    }

    private func captureFrame() throws {
        guard let view, let directory = temporaryDirectory else {
            throw TerminalRecordingError.unableToCapture
        }
        captureCount += 1
        let now = Date()
        let keyLabel = latestKeyLabel.flatMap { label in
            now.timeIntervalSince(label.date)
                <= TerminalRecordingConfiguration.keyLabelDuration
                ? label
                : nil
        }
        let representation = try TerminalFrameCapture.representation(of: view)

        // Nothing moved since the last tick: give the frame already on disk
        // another tick of playback time rather than writing the same pixels
        // again. A terminal recording is mostly made of these — a 60s one
        // wrote up to 480 PNGs, most of them byte-identical, at roughly 2MB
        // apiece.
        //
        // This is about the cost of recording, not the size of the GIF:
        // ImageIO already writes unchanged frames as inter-frame diffs, so
        // a duplicate costs about 26 bytes in the output either way.
        if var last = frames.last,
           last.ticks < TerminalRecordingConfiguration.maximumFrameRunTicks,
           matchesPreviousSample(representation, keyLabel: keyLabel) {
            last.ticks += 1
            frames[frames.count - 1] = last
            return
        }

        let image = try TerminalFrameCapture.image(
            from: representation,
            pointSize: view.bounds.size,
            keyLabel: keyLabel?.text,
            keyLabelCursorRect: keyLabel?.cursorRect
        )
        let url = directory.appendingPathComponent(
            String(format: "%04d.png", frames.count)
        )
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw TerminalRecordingError.unableToWriteFrame }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TerminalRecordingError.unableToWriteFrame
        }
        frames.append(RecordedFrame(url: url, ticks: 1))
        rememberSample(representation, keyLabel: keyLabel)
    }

    private func matchesPreviousSample(
        _ representation: NSBitmapImageRep,
        keyLabel: (text: String, date: Date, cursorRect: NSRect)?
    ) -> Bool {
        // A planar or unreadable representation, or a pane that changed
        // size, falls back to writing every frame — the behavior this
        // deduplication replaced.
        guard !representation.isPlanar,
              let data = representation.bitmapData,
              let previous = previousSignature,
              previous.width == representation.pixelsWide,
              previous.height == representation.pixelsHigh,
              previous.bytesPerRow == representation.bytesPerRow,
              previous.keyLabel == keyLabel?.text,
              previous.keyLabelCursorRect == keyLabel?.cursorRect
        else { return false }
        let count = representation.bytesPerRow * representation.pixelsHigh
        guard previous.bytes.count == count else { return false }
        return previous.bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return false }
            return memcmp(base, data, count) == 0
        }
    }

    private func rememberSample(
        _ representation: NSBitmapImageRep,
        keyLabel: (text: String, date: Date, cursorRect: NSRect)?
    ) {
        guard !representation.isPlanar,
              let data = representation.bitmapData
        else {
            previousSignature = nil
            return
        }
        let count = representation.bytesPerRow * representation.pixelsHigh
        var bytes: [UInt8]
        if var existing = previousSignature?.bytes, existing.count == count {
            // Same geometry as last tick: overwrite in place instead of
            // handing back ~17MB to the allocator eight times a second.
            existing.withUnsafeMutableBytes { buffer in
                if let base = buffer.baseAddress {
                    base.copyMemory(from: data, byteCount: count)
                }
            }
            bytes = existing
        } else {
            bytes = [UInt8](UnsafeBufferPointer(start: data, count: count))
        }
        previousSignature = FrameSignature(
            bytes: bytes,
            width: representation.pixelsWide,
            height: representation.pixelsHigh,
            bytesPerRow: representation.bytesPerRow,
            keyLabel: keyLabel?.text,
            keyLabelCursorRect: keyLabel?.cursorRect
        )
    }

    /// The frames written so far and how many ticks each one covers.
    var recordedFrameTicks: [Int] { frames.map(\.ticks) }
}
