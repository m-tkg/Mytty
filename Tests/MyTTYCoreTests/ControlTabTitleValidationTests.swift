import Testing

@testable import MyTTYCore

@Suite("Control tab title validation")
struct ControlTabTitleValidationTests {
    @Test("accepts ordinary, Japanese and empty titles")
    func acceptsOrdinary() {
        #expect(ControlTabTitleValidation.isValid("Build"))
        #expect(ControlTabTitleValidation.isValid("ワーカーA"))
        #expect(ControlTabTitleValidation.isValid(""))
        #expect(ControlTabTitleValidation.isValid("   "))
    }

    @Test("rejects control characters and over-long titles")
    func rejectsInvalid() {
        #expect(!ControlTabTitleValidation.isValid("a\nb"))
        #expect(!ControlTabTitleValidation.isValid("a\u{1B}[31mb"))
        #expect(!ControlTabTitleValidation.isValid(
            String(repeating: "x", count: ControlTabTitleValidation.maximumScalars + 1)
        ))
        #expect(ControlTabTitleValidation.isValid(
            String(repeating: "x", count: ControlTabTitleValidation.maximumScalars)
        ))
    }

    @Test("a spawn tab title must be nonempty after trimming")
    func spawnTitleNonempty() {
        #expect(ControlTabTitleValidation.isValidForSpawn("worker"))
        #expect(!ControlTabTitleValidation.isValidForSpawn(""))
        #expect(!ControlTabTitleValidation.isValidForSpawn("  "))
        #expect(!ControlTabTitleValidation.isValidForSpawn("a\tb"))
    }
}
