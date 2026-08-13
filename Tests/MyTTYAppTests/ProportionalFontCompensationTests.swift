import Testing

@testable import MyTTYApp

@Suite("Proportional font compensation")
struct ProportionalFontCompensationTests {
    @Test("treats an equal max and target advance as monospace-like")
    func equalAdvancesNeedNoCompensation() {
        #expect(
            ProportionalFontCompensation.percent(
                maxAdvance: 10,
                targetAdvance: 10
            ) == nil
        )
    }

    @Test("derives a shrink percentage for a proportional-sized advance gap")
    func proportionalAdvanceGap() {
        let percent = ProportionalFontCompensation.percent(
            maxAdvance: 12,
            targetAdvance: 7
        )
        #expect(percent != nil)
        #expect(percent! <= -40 && percent! >= -44)
    }

    @Test("skips a gap under 2%, too small to be worth a config write")
    func smallGapNeedsNoCompensation() {
        #expect(
            ProportionalFontCompensation.percent(
                maxAdvance: 100,
                targetAdvance: 99
            ) == nil
        )
    }

    @Test("rejects a non-positive max advance")
    func zeroMaxAdvanceIsInvalid() {
        #expect(
            ProportionalFontCompensation.percent(
                maxAdvance: 0,
                targetAdvance: 5
            ) == nil
        )
    }

    @Test("rejects a non-positive target advance")
    func zeroTargetAdvanceIsInvalid() {
        #expect(
            ProportionalFontCompensation.percent(
                maxAdvance: 10,
                targetAdvance: 0
            ) == nil
        )
    }

    @Test("computes a percentage string for a proportional system font")
    func proportionalSystemFont() {
        let value = ProportionalFontCompensation.adjustCellWidthValue(
            forFamily: "Helvetica"
        )
        #expect(value != nil)
        #expect(value!.hasPrefix("-"))
        #expect(value!.hasSuffix("%"))
    }

    @Test("leaves a monospace system font uncompensated")
    func monospaceSystemFont() {
        #expect(
            ProportionalFontCompensation.adjustCellWidthValue(
                forFamily: "Menlo"
            ) == nil
        )
    }

    @Test("returns nil for a font family that doesn't resolve")
    func unresolvedFontFamily() {
        #expect(
            ProportionalFontCompensation.adjustCellWidthValue(
                forFamily: "NoSuchFontFamily12345"
            ) == nil
        )
    }

    @Test("returns nil for an empty font family")
    func emptyFontFamily() {
        #expect(
            ProportionalFontCompensation.adjustCellWidthValue(
                forFamily: ""
            ) == nil
        )
    }
}
