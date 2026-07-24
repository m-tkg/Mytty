import Carbon.HIToolbox

/// Forces the macOS input source to an ASCII-capable one (e.g. U.S., not a
/// Japanese/Chinese/Korean IME), used when focus returns to Mytty at a bare
/// shell prompt so the user isn't left typing into a non-ASCII input method
/// meant for whatever app previously had focus.
enum ASCIIInputSourceSwitcher {
    @MainActor
    static func switchToASCIIIfNeeded() {
        if let current = TISCopyCurrentKeyboardInputSource()?
            .takeRetainedValue(),
            isASCIICapable(current) {
            return
        }
        guard let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?
            .takeRetainedValue()
        else { return }
        TISSelectInputSource(ascii)
    }

    private static func isASCIICapable(_ source: TISInputSource) -> Bool {
        guard let raw = TISGetInputSourceProperty(
            source,
            kTISPropertyInputSourceIsASCIICapable
        ) else { return false }
        return CFBooleanGetValue(
            Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue()
        )
    }
}
