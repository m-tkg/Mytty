import AppKit
import ImageIO
import MyTTYCore
import UniformTypeIdentifiers

enum TerminalRecordingConfiguration {
    static let maximumDuration: TimeInterval = 60
    static let framesPerSecond = 8
    static let maximumFrameCount = Int(maximumDuration)
        * framesPerSecond
    static let frameDelay = 1 / Double(framesPerSecond)
    static let maximumPixelDimension = 4_096
    static let keyLabelDuration: TimeInterval = 1.2
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

struct AnimatedGIFEncoder: Sendable {
    func encode(
        frames: [CGImage],
        frameDelay: TimeInterval,
        to outputURL: URL
    ) throws {
        try encode(
            frameCount: frames.count,
            frameDelay: frameDelay,
            outputURL: outputURL,
            imageAt: { frames[$0] }
        )
    }

    func encode(
        frameURLs: [URL],
        frameDelay: TimeInterval,
        to outputURL: URL
    ) throws {
        try encode(
            frameCount: frameURLs.count,
            frameDelay: frameDelay,
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
                return image
            }
        )
    }

    private func encode(
        frameCount: Int,
        frameDelay: TimeInterval,
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
        let properties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
            ],
        ] as CFDictionary
        for index in 0..<frameCount {
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
    static func image(
        from view: NSView,
        keyLabel: String?,
        keyLabelCursorRect: NSRect? = nil
    ) throws -> CGImage {
        view.layoutSubtreeIfNeeded()
        guard view.bounds.width >= 1,
              view.bounds.height >= 1,
              let representation = view.bitmapImageRepForCachingDisplay(
                  in: view.bounds
              )
        else { throw TerminalRecordingError.unableToCapture }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let source = representation.cgImage else {
            throw TerminalRecordingError.unableToCapture
        }

        let size = targetPixelSize(
            source: source,
            pointSize: view.bounds.size
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
                CGFloat(size.width) / view.bounds.width,
                CGFloat(size.height) / view.bounds.height
            )
            let frame = keyLabelFrame(
                keyLabel: keyLabel,
                cursorRect: keyLabelCursorRect,
                in: view.bounds
            )
            draw(
                keyLabel: keyLabel,
                in: context,
                frame: frame,
                bounds: view.bounds,
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
        let targetScale = min(sourceScale, maximumIntegralScale)
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
    private var frameURLs: [URL] = []
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
        completion: @escaping @MainActor (
            Result<URL, TerminalRecordingError>
        ) -> Void
    ) {
        stopCapturing()
        let frames = frameURLs
        let directory = temporaryDirectory
        frameURLs.removeAll()
        temporaryDirectory = nil

        Task {
            let result = await Task.detached(priority: .utility) {
                () -> Result<URL, TerminalRecordingError> in
                guard !frames.isEmpty else { return .failure(.noFrames) }
                guard let directory else {
                    return .failure(.unableToCreateTemporaryDirectory)
                }
                let encoded = directory.appendingPathComponent("recording.gif")
                do {
                    try AnimatedGIFEncoder().encode(
                        frameURLs: frames,
                        frameDelay: TerminalRecordingConfiguration.frameDelay,
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
        frameURLs.removeAll()
    }

    @objc private func captureTimerFired(_ timer: Timer) {
        let elapsed = startedAt.map { Date().timeIntervalSince($0) }
            ?? TerminalRecordingConfiguration.maximumDuration
        guard elapsed < TerminalRecordingConfiguration.maximumDuration,
              frameURLs.count
                < TerminalRecordingConfiguration.maximumFrameCount
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
        let now = Date()
        let keyLabel = latestKeyLabel.flatMap { label in
            now.timeIntervalSince(label.date)
                <= TerminalRecordingConfiguration.keyLabelDuration
                ? label
                : nil
        }
        let image = try TerminalFrameCapture.image(
            from: view,
            keyLabel: keyLabel?.text,
            keyLabelCursorRect: keyLabel?.cursorRect
        )
        let url = directory.appendingPathComponent(
            String(format: "%04d.png", frameURLs.count)
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
        frameURLs.append(url)
    }
}
