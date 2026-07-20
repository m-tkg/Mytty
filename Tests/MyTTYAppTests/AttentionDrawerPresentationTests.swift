import Testing

@testable import MyTTYApp

@Suite("Attention drawer presentation")
struct AttentionDrawerPresentationTests {
    @Test("uses a Return symbol for moving to the shell")
    func moveToShellSymbol() {
        #expect(AttentionFocusControlPresentation.symbolName == "return")
    }
}
