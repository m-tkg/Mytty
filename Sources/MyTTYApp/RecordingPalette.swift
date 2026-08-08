import CoreGraphics
import Foundation
import ImageIO

/// One palette shared by every frame of a recording.
///
/// GIF indexes each frame into at most 256 colors. Left to itself, ImageIO
/// picks those colors per frame and dithers whatever does not fit, which is
/// expensive twice over: dithering is high-entropy noise that LZW cannot
/// compress, and a palette that drifts between frames breaks up runs that
/// would otherwise repeat. Choosing the colors once, up front, and mapping
/// every frame through them keeps flat areas byte-identical across frames.
///
/// Terminal pixels are a good fit: a screenshot of a pane holds a few
/// hundred distinct colors, nearly all of them antialiasing steps between
/// the same handful of foreground and background colors.
struct RecordingPalette: Equatable {
    /// Palette entries as `0x00BBGGRR` — the byte order the mapper reads
    /// and writes, which is `CGImageAlphaInfo.noneSkipLast` on a
    /// little-endian machine.
    let colors: [UInt32]
    /// Nearest palette entry for each 5-5-5 bucket of the RGB cube, so
    /// mapping a pixel is one array lookup rather than a search.
    private let lookup: [UInt8]

    init(colors: [UInt32]) {
        precondition(!colors.isEmpty && colors.count <= 256)
        self.colors = colors
        var lookup = [UInt8](repeating: 0, count: 1 << 15)
        let components = colors.map { RecordingPalette.components($0) }
        for bucket in 0..<(1 << 15) {
            // Bucket centers: the low bits the 5-5-5 index dropped are
            // filled back in so a bucket maps to the middle of its range.
            let red = ((bucket >> 10) & 31) << 3 | 4
            let green = ((bucket >> 5) & 31) << 3 | 4
            let blue = (bucket & 31) << 3 | 4
            var best = 0
            var bestDistance = Int.max
            for (index, color) in components.enumerated() {
                let dr = red - color.red
                let dg = green - color.green
                let db = blue - color.blue
                let distance = dr * dr + dg * dg + db * db
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
            }
            lookup[bucket] = UInt8(best)
        }
        self.lookup = lookup
    }

    func mapped(_ pixel: UInt32) -> UInt32 {
        let (red, green, blue) = Self.components(pixel)
        let bucket = ((red >> 3) << 10) | ((green >> 3) << 5) | (blue >> 3)
        return colors[Int(lookup[bucket])]
    }

    static func components(_ pixel: UInt32) -> (red: Int, green: Int, blue: Int) {
        (
            Int(pixel & 0xFF),
            Int((pixel >> 8) & 0xFF),
            Int((pixel >> 16) & 0xFF)
        )
    }
}

/// Picks the palette for a recording: the smallest one that still describes
/// the pixels faithfully.
///
/// A terminal collapses to 32 colors with no visible loss, while a pane
/// showing a photograph does not — so the size is chosen from the error it
/// would cause rather than assumed. Anything that cannot be described well
/// even at 256 colors is left alone for ImageIO to handle.
enum RecordingPaletteBuilder {
    /// Candidate sizes, smallest first.
    static let candidateSizes = [32, 64, 128, 256]
    /// Largest acceptable root-mean-square error per channel, weighted by
    /// how many pixels each color covers. Calibrated against real
    /// recordings: a pane of colored terminal output lands on 32 colors at
    /// an error of 1.8, while a gradient or a photograph is pushed to the
    /// largest palette or refused outright. Sixteen colors was measured
    /// too — worth another 3% of file size at an error of 4.7, which
    /// visibly coarsens the antialiasing around glyphs — so the limit sits
    /// below it deliberately.
    static let maximumError = 3.0

    /// How many frames are sampled when building the histogram. Terminal
    /// colors barely change over a recording, so a spread of frames
    /// describes the whole of it, and this keeps the extra decode off the
    /// critical path for long recordings.
    static let maximumSampledFrames = 12

    /// Builds the palette from a spread of the frames on disk, decoding
    /// only the ones it samples.
    static func build(samplingFramesAt urls: [URL]) -> RecordingPalette? {
        build(sampling: sample(urls).compactMap(decode(_:)))
    }

    private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func build(sampling frames: [CGImage]) -> RecordingPalette? {
        let entries = histogram(of: frames)
        guard !entries.isEmpty else { return nil }
        // Every size is tried, even when the recording would already fit
        // 256 colors: a pane that happens to hold 250 of them still encodes
        // far smaller at 32, and the error check is what decides whether it
        // may.
        if let smallest = candidateSizes.first, entries.count <= smallest {
            return RecordingPalette(colors: entries.map(\.color))
        }
        // One median cut, stopped at each candidate size on the way up, so
        // the smallest acceptable palette costs one pass rather than four.
        for colors in medianCutCandidates(entries) {
            let palette = RecordingPalette(colors: colors)
            if error(of: palette, over: entries) <= maximumError {
                return palette
            }
        }
        return nil
    }

    /// Color counts across the sampled frames, bucketed into the 5-5-5 cube
    /// so a photograph cannot blow the histogram up to a million entries.
    /// Each bucket is represented by the most common *exact* color inside
    /// it: a terminal's background has to survive as itself, since a
    /// background that drifted by a step would change every pixel of every
    /// frame and undo the encoder's inter-frame diffing.
    static func histogram(of frames: [CGImage]) -> [Entry] {
        var buckets: [UInt16: [UInt32: Int]] = [:]
        for frame in frames {
            guard let pixels = RecordingPixelBuffer.read(frame) else { continue }
            for pixel in pixels.pixels {
                let color = pixel & 0x00FF_FFFF
                buckets[bucket(of: color), default: [:]][color, default: 0] += 1
            }
        }
        return buckets.values.compactMap { colors in
            guard let representative = colors.max(by: { $0.value < $1.value })
            else { return nil }
            return Entry(
                color: representative.key,
                count: colors.values.reduce(0, +)
            )
        }
    }

    private static func bucket(of color: UInt32) -> UInt16 {
        let (red, green, blue) = RecordingPalette.components(color)
        return UInt16((red >> 3) << 10 | (green >> 3) << 5 | (blue >> 3))
    }

    static func sample<Frame>(_ frames: [Frame]) -> [Frame] {
        guard frames.count > maximumSampledFrames else { return frames }
        let stride = Double(frames.count) / Double(maximumSampledFrames)
        return (0..<maximumSampledFrames).map {
            frames[min(frames.count - 1, Int(Double($0) * stride))]
        }
    }

    /// Weighted RMSE per channel between the entries and what the palette
    /// would render them as.
    static func error(
        of palette: RecordingPalette,
        over entries: [Entry]
    ) -> Double {
        var squared = 0.0
        var total = 0.0
        for entry in entries {
            let source = RecordingPalette.components(entry.color)
            let mapped = RecordingPalette.components(palette.mapped(entry.color))
            let dr = Double(source.red - mapped.red)
            let dg = Double(source.green - mapped.green)
            let db = Double(source.blue - mapped.blue)
            squared += Double(entry.count) * (dr * dr + dg * dg + db * db) / 3
            total += Double(entry.count)
        }
        guard total > 0 else { return 0 }
        return (squared / total).squareRoot()
    }

    struct Entry: Equatable {
        let color: UInt32
        let count: Int
    }

    /// A box of colors, carrying the statistics the split loop would
    /// otherwise recompute for every box on every split.
    private struct Box {
        var entries: [Entry]
        var channel: Int
        var spread: Int
        var pixels: Int

        init(_ entries: [Entry]) {
            self.entries = entries
            var widest = 0
            var widestRange = -1
            for channel in 0..<3 {
                var low = 255
                var high = 0
                for entry in entries {
                    let value = component(entry.color, channel)
                    low = min(low, value)
                    high = max(high, value)
                }
                if high - low > widestRange {
                    widestRange = high - low
                    widest = channel
                }
            }
            channel = widest
            spread = max(0, widestRange)
            pixels = entries.reduce(0) { $0 + $1.count }
        }
    }

    /// Median cut, yielding the palette at each candidate size as it goes.
    /// Boxes are split widest-first, weighting the spread by how many
    /// pixels the box covers so a wide but nearly unused range does not
    /// win a palette entry away from the colors the eye actually sees.
    static func medianCutCandidates(_ entries: [Entry]) -> [[UInt32]] {
        var boxes = [Box(entries)]
        var candidates: [[UInt32]] = []
        for size in candidateSizes {
            while boxes.count < size {
                guard let index = boxes.indices
                    .filter({ boxes[$0].entries.count > 1 })
                    .max(by: {
                        boxes[$0].spread * boxes[$0].pixels
                            < boxes[$1].spread * boxes[$1].pixels
                    })
                else { break }
                let box = boxes[index]
                let sorted = box.entries.sorted {
                    component($0.color, box.channel)
                        < component($1.color, box.channel)
                }
                // Split at the weighted median so both halves carry a
                // similar number of pixels, not of distinct colors.
                var carried = 0
                var cut = 1
                for (offset, entry) in sorted.enumerated() {
                    carried += entry.count
                    if carried * 2 >= box.pixels {
                        cut = min(max(1, offset + 1), sorted.count - 1)
                        break
                    }
                }
                boxes[index] = Box(Array(sorted[..<cut]))
                boxes.append(Box(Array(sorted[cut...])))
            }
            candidates.append(boxes.compactMap { box in
                box.entries.max { $0.count < $1.count }?.color
            })
            if boxes.count < size { break }
        }
        return candidates
    }

    private static func component(_ color: UInt32, _ channel: Int) -> Int {
        Int((color >> (UInt32(channel) * 8)) & 0xFF)
    }
}

/// A frame's pixels in a known layout, so palette code never has to care
/// what the capture handed back.
enum RecordingPixelBuffer {
    struct Buffer {
        var pixels: [UInt32]
        let width: Int
        let height: Int
    }

    static func read(_ image: CGImage) -> Buffer? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt32](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard drawn else { return nil }
        return Buffer(pixels: pixels, width: width, height: height)
    }

    static func image(_ buffer: Buffer) -> CGImage? {
        var pixels = buffer.pixels
        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: buffer.width,
                height: buffer.height,
                bitsPerComponent: 8,
                bytesPerRow: buffer.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
    }

    /// The frame rendered through `palette`. Returns the original when the
    /// pixels cannot be read, so a failure here costs size, never a frame.
    static func mapped(_ image: CGImage, through palette: RecordingPalette) -> CGImage {
        guard var buffer = read(image) else { return image }
        for index in buffer.pixels.indices {
            buffer.pixels[index] = palette.mapped(buffer.pixels[index])
        }
        return RecordingPixelBuffer.image(buffer) ?? image
    }
}
