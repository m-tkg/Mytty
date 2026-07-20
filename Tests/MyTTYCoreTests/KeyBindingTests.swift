import Foundation
import Testing

@testable import MyTTYCore

@Suite("Key bindings")
struct KeyBindingTests {
    @Test("round trips semantic keys and normalized modifiers")
    func serialization() throws {
        let binding = try #require(
            MyTTYKeyBinding(serialized: "shift+command+option+left")
        )

        #expect(binding.key == "left")
        #expect(binding.modifiers == [.command, .option, .shift])
        #expect(binding.serialized == "option+shift+command+left")
        #expect(binding.displayName == "⌥⇧⌘←")
        #expect(MyTTYKeyBinding(serialized: "command+") == nil)
        #expect(MyTTYKeyBinding(serialized: "hyper+d") == nil)
    }

    @Test("normalizes shifted punctuation to its base key")
    func shiftedPunctuation() throws {
        let binding = try #require(
            MyTTYKeyBinding(
                serialized: "control+shift+command+|"
            )
        )

        #expect(binding.key == "backslash")
        #expect(binding.modifiers == [.control, .shift, .command])
        #expect(
            binding.serialized
                == "control+shift+command+backslash"
        )
    }

    @Test("provides defaults for every menu command that has a shortcut")
    func defaults() {
        let bindings = MyTTYCommand.defaultKeyBindings

        #expect(bindings[.settings]?.serialized == "command+comma")
        #expect(bindings[.splitRight]?.serialized == "command+d")
        #expect(bindings[.splitDown]?.serialized == "shift+command+d")
        #expect(bindings[.renameTab]?.serialized == "command+r")
        #expect(bindings[.openHTML]?.serialized == "command+o")
        #expect(bindings[.findInPane]?.serialized == "control+f")
        #expect(
            bindings[.showPaneList]?.serialized
                == "control+command+p"
        )
        #expect(bindings[.toggleTabPanel]?.serialized == "command+b")
        #expect(
            bindings[.toggleRecording]?.serialized == "shift+command+g"
        )
        #expect(
            bindings[.equalizePanes]?.serialized
                == "control+command+equal"
        )
        #expect(
            bindings[.togglePaneZoom]?.serialized
                == "control+command+return"
        )
        #expect(
            bindings[.focusLeft]?.serialized
                == "option+command+left"
        )
        #expect(bindings[.splitLeft] == nil)
        #expect(bindings[.splitUp] == nil)
    }

    @Test("reports every command sharing the same shortcut")
    func conflicts() {
        let duplicate = MyTTYKeyBinding(
            key: "d",
            modifiers: [.command]
        )
        let bindings: [MyTTYCommand: MyTTYKeyBinding] = [
            .newTab: duplicate,
            .splitRight: duplicate,
            .toggleRecording: MyTTYKeyBinding(
                key: "a",
                modifiers: [.command, .shift]
            ),
        ]

        #expect(
            MyTTYKeyBindingConflicts.commands(
                conflictingWith: .newTab,
                in: bindings
            ) == [.splitRight]
        )
        #expect(
            MyTTYKeyBindingConflicts.commands(
                conflictingWith: .toggleRecording,
                in: bindings
            ).isEmpty
        )
    }
}
