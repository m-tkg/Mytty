import SwiftUI
import Testing

@testable import MyTTYApp

struct OrchestrationSettingsViewTests {
    @Test("Installed command line tool checkmark is green")
    func installedCheckmarkTint() {
        #expect(CommandLineToolStatusStyle.installedTint == Color.green)
    }

    @Test("Installed command line tool uses a filled checkmark symbol")
    func installedCheckmarkSymbol() {
        #expect(CommandLineToolStatusStyle.installedSymbolName == "checkmark.circle.fill")
    }
}
