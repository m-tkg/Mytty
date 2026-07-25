import Carbon.HIToolbox
import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Carbon key code conversion")
struct CarbonKeyCodeTests {
    @Test("converts a plain letter binding")
    func letterBinding() throws {
        let binding = MyTTYKeyBinding(key: "t", modifiers: [.command])
        let hotKey = try #require(CarbonKeyCode.hotKey(for: binding))

        #expect(hotKey.keyCode == UInt32(kVK_ANSI_T))
        #expect(hotKey.modifierFlags == UInt32(cmdKey))
    }

    @Test("converts a digit binding")
    func digitBinding() throws {
        let binding = MyTTYKeyBinding(key: "1", modifiers: [.command])
        let hotKey = try #require(CarbonKeyCode.hotKey(for: binding))

        #expect(hotKey.keyCode == UInt32(kVK_ANSI_1))
    }

    @Test("converts named keys (space, return, left, comma)")
    func namedKeys() throws {
        #expect(
            CarbonKeyCode.virtualKeyCode(for: "space")
                == UInt32(kVK_Space)
        )
        #expect(
            CarbonKeyCode.virtualKeyCode(for: "return")
                == UInt32(kVK_Return)
        )
        #expect(
            CarbonKeyCode.virtualKeyCode(for: "left")
                == UInt32(kVK_LeftArrow)
        )
        #expect(
            CarbonKeyCode.virtualKeyCode(for: "comma")
                == UInt32(kVK_ANSI_Comma)
        )
    }

    @Test("combines every modifier into the Carbon modifier mask")
    func combinesModifiers() {
        let flags = CarbonKeyCode.modifierFlags(
            for: [.control, .option, .shift, .command]
        )
        #expect(flags & UInt32(controlKey) != 0)
        #expect(flags & UInt32(optionKey) != 0)
        #expect(flags & UInt32(shiftKey) != 0)
        #expect(flags & UInt32(cmdKey) != 0)
    }

    @Test("the default floating-pane binding (control+option+command+t) converts")
    func defaultFloatingPaneBinding() throws {
        let binding = try #require(
            MyTTYCommand.defaultKeyBindings[.toggleFloatingPane]
        )
        let hotKey = try #require(CarbonKeyCode.hotKey(for: binding))

        #expect(hotKey.keyCode == UInt32(kVK_ANSI_T))
        #expect(
            hotKey.modifierFlags
                == UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
        )
    }
}
