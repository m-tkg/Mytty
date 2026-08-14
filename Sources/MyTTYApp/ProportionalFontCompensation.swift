import CoreGraphics
import CoreText
import Foundation

/// Ghostty sizes a terminal cell to the *widest* horizontal advance among
/// the primary font's printable ASCII glyphs. For a monospace font every
/// glyph has (roughly) the same advance, so the widest one is a fair
/// stand-in for the whole alphabet. For a proportional font (Helvetica and
/// friends) the widest glyph is usually a capital M or W, and that width
/// gets applied to every cell -- narrow letters like "i" or "l" end up
/// stranded in a cell built for "M", and text reads as loosely spaced.
///
/// Ghostty exposes `adjust-cell-width` (e.g. `"-38%"`) to shrink the derived
/// cell width by a percentage. This type computes that percentage from the
/// font itself: it measures the same ASCII advances Ghostty measures, then
/// compares the widest one against the advance of a representative
/// character (the average of lowercase letters and digits) to work out how
/// far the cell should shrink to fit that representative width instead.
enum ProportionalFontCompensation {
    /// The ASCII printable range Ghostty measures when it derives a
    /// primary font's cell width.
    private static let asciiPrintableRange: ClosedRange<UInt16> = 0x20...0x7E

    /// Computes the `adjust-cell-width` value for `family`, or nil when no
    /// compensation is needed: the family doesn't resolve, is monospace, or
    /// the widest glyph is already close enough to the representative width
    /// that a config write wouldn't be noticeable.
    static func adjustCellWidthValue(
        forFamily family: String,
        size: CGFloat = 13
    ) -> String? {
        guard !family.isEmpty else { return nil }

        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: family,
        ] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)

        // CTFontCreateWithFontDescriptor never fails outright -- an
        // unresolvable family falls back to some system font instead.
        // Comparing the resolved family name catches that fallback so a
        // typo'd or uninstalled family is treated as "no compensation"
        // rather than compensating for whatever font CoreText substituted.
        let resolvedFamily = CTFontCopyFamilyName(font) as String
        guard resolvedFamily.caseInsensitiveCompare(family) == .orderedSame
        else { return nil }

        guard !CTFontGetSymbolicTraits(font).contains(.traitMonoSpace) else {
            return nil
        }

        var maxAdvance: Double = 0
        var targetAdvances: [Double] = []
        for codepoint in asciiPrintableRange {
            guard let scalar = Unicode.Scalar(codepoint),
                  let advance = horizontalAdvance(of: scalar, in: font)
            else { continue }
            maxAdvance = max(maxAdvance, advance)
            if isRepresentativeCharacter(scalar) {
                targetAdvances.append(advance)
            }
        }
        guard !targetAdvances.isEmpty else { return nil }

        // The 75th percentile of the representative advances: tight enough
        // to close the gaps around narrow glyphs, wide enough that the
        // occasional capital doesn't bury its neighbors under its overflow.
        let sorted = targetAdvances.sorted()
        let target = sorted[min(
            sorted.count - 1,
            Int(Double(sorted.count) * 0.75)
        )]
        guard let percent = percent(
            maxAdvance: maxAdvance,
            targetAdvance: target
        ) else { return nil }
        return "\(percent)%"
    }

    /// The pure arithmetic behind `adjustCellWidthValue`, split out so it's
    /// testable without touching CoreText: what percentage narrows a cell
    /// built for `maxAdvance` down to `targetAdvance`. Nil when either
    /// input is non-positive, or the two are already within 2% of each
    /// other -- close enough that writing `adjust-cell-width` wouldn't be
    /// worth the config churn.
    static func percent(maxAdvance: Double, targetAdvance: Double) -> Int? {
        guard maxAdvance > 0, targetAdvance > 0 else { return nil }
        let percent = Int((targetAdvance / maxAdvance * 100).rounded()) - 100
        guard !(-2...0).contains(percent) else { return nil }
        return percent
    }

    /// Letters and digits: the characters most representative of a font's
    /// "typical" width, used as the target the widest glyph gets compensated
    /// toward. Uppercase is included deliberately -- compensating down to a
    /// lowercase-only average makes capitals overflow so far into the next
    /// cell that they cover its glyph entirely.
    private static func isRepresentativeCharacter(
        _ scalar: Unicode.Scalar
    ) -> Bool {
        (scalar.value >= 0x61 && scalar.value <= 0x7A) // a-z
            || (scalar.value >= 0x41 && scalar.value <= 0x5A) // A-Z
            || (scalar.value >= 0x30 && scalar.value <= 0x39) // 0-9
    }

    private static func horizontalAdvance(
        of scalar: Unicode.Scalar,
        in font: CTFont
    ) -> Double? {
        var utf16 = Array(String(scalar).utf16)
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &utf16, &glyph, 1),
              glyph != 0
        else { return nil }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        return Double(advance.width)
    }
}
