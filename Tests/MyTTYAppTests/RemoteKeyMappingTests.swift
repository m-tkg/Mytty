import AppKit
import Testing

@testable import MyTTYApp

@Suite("Remote key mapping")
struct RemoteKeyMappingTests {
    @Test("maps named keys to their macOS virtual key codes")
    func mapsNamedKeys() {
        #expect(
            RemoteKeyMapping.event(key: "escape", modifiers: [])
                == RemoteKeyMapping.KeyEvent(
                    keyCode: 53,
                    characters: "\u{1B}",
                    modifierFlags: []
                )
        )
        #expect(
            RemoteKeyMapping.event(key: "delete", modifiers: [])
                == RemoteKeyMapping.KeyEvent(
                    keyCode: 51,
                    characters: "\u{7F}",
                    modifierFlags: []
                )
        )
        #expect(
            RemoteKeyMapping.event(key: "up", modifiers: [])
                == RemoteKeyMapping.KeyEvent(
                    keyCode: 126,
                    characters: "\u{F700}",
                    modifierFlags: []
                )
        )
        #expect(
            RemoteKeyMapping.event(key: "f12", modifiers: [])
                == RemoteKeyMapping.KeyEvent(
                    keyCode: 111,
                    characters: "\u{F70F}",
                    modifierFlags: []
                )
        )
    }

    @Test("maps character keys with modifiers for combos like Ctrl+C")
    func mapsCharacterKeysWithModifiers() {
        #expect(
            RemoteKeyMapping.event(key: "c", modifiers: ["control"])
                == RemoteKeyMapping.KeyEvent(
                    keyCode: 8,
                    characters: "c",
                    modifierFlags: [.control]
                )
        )
        #expect(
            RemoteKeyMapping.event(
                key: "left",
                modifiers: ["option", "shift"]
            )
                == RemoteKeyMapping.KeyEvent(
                    keyCode: 123,
                    characters: "\u{F702}",
                    modifierFlags: [.option, .shift]
                )
        )
    }

    @Test("returns nil for keys it cannot map")
    func unknownKeysReturnNil() {
        #expect(RemoteKeyMapping.event(key: "hyper", modifiers: []) == nil)
        #expect(RemoteKeyMapping.event(key: "あ", modifiers: []) == nil)
        #expect(RemoteKeyMapping.event(key: "", modifiers: []) == nil)
    }
}
