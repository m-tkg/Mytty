import AppKit
import MyTTYCore

@MainActor
final class KeyBindingRecorderButton: NSButton {
    private var binding: MyTTYKeyBinding?
    private var notSetTitle: String
    private var recordingTitle: String
    private let onChange: (MyTTYKeyBinding?) -> Void
    private var eventMonitor: Any?
    private(set) var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    init(
        binding: MyTTYKeyBinding?,
        notSetTitle: String = "Not Set",
        recordingTitle: String = "Recording...",
        onChange: @escaping (MyTTYKeyBinding?) -> Void
    ) {
        self.binding = binding
        self.notSetTitle = notSetTitle
        self.recordingTitle = recordingTitle
        self.onChange = onChange
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        stopMonitoringKeyEvents()
    }

    func setBinding(_ binding: MyTTYKeyBinding?) {
        self.binding = binding
        if !isRecording {
            updateTitle()
        }
    }

    func updateTitles(
        notSetTitle: String,
        recordingTitle: String
    ) {
        self.notSetTitle = notSetTitle
        self.recordingTitle = recordingTitle
        if !isRecording {
            updateTitle()
        }
    }

    @objc func beginRecording() {
        isRecording = true
        title = recordingTitle
        startMonitoringKeyEvents()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:
            finish(with: nil)
        case 53:
            cancelRecording()
        default:
            guard let binding = MyTTYKeyBinding(event: event) else {
                NSSound.beep()
                return
            }
            finish(with: binding)
        }
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, isRecording {
            cancelRecording()
        }
        return didResign
    }

    private func finish(with binding: MyTTYKeyBinding?) {
        self.binding = binding
        isRecording = false
        stopMonitoringKeyEvents()
        updateTitle()
        onChange(binding)
        window?.makeFirstResponder(nil)
    }

    private func cancelRecording() {
        isRecording = false
        stopMonitoringKeyEvents()
        updateTitle()
        window?.makeFirstResponder(nil)
    }

    private func startMonitoringKeyEvents() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.keyDown(with: event)
            return nil
        }
    }

    private func stopMonitoringKeyEvents() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func updateTitle() {
        title = binding?.displayName ?? notSetTitle
    }
}

extension MyTTYKeyBinding {
    var appKitKeyEquivalent: String {
        switch key {
        case "left": "\u{F702}"
        case "right": "\u{F703}"
        case "up": "\u{F700}"
        case "down": "\u{F701}"
        case "return": "\r"
        case "tab": "\t"
        case "space": " "
        case "escape": "\u{1B}"
        case "home": "\u{F729}"
        case "end": "\u{F72B}"
        case "page-up": "\u{F72C}"
        case "page-down": "\u{F72D}"
        case "comma": ","
        case "period": "."
        case "slash": "/"
        case "semicolon": ";"
        case "quote": "'"
        case "left-bracket": "["
        case "right-bracket": "]"
        case "backslash": "\\"
        case "backtick": "`"
        case "minus": "-"
        case "equal": "="
        case "plus": "+"
        default: key
        }
    }

    var appKitModifierMask: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier {
            case .control: result.insert(.control)
            case .option: result.insert(.option)
            case .shift: result.insert(.shift)
            case .command: result.insert(.command)
            }
        }
        return result
    }

    init?(event: NSEvent) {
        let keyCodeNames: [UInt16: String] = [
            24: "equal",
            27: "minus",
            30: "right-bracket",
            33: "left-bracket",
            36: "return",
            39: "quote",
            41: "semicolon",
            42: "backslash",
            43: "comma",
            44: "slash",
            47: "period",
            48: "tab",
            49: "space",
            50: "backtick",
            53: "escape",
            115: "home",
            116: "page-up",
            119: "end",
            121: "page-down",
            123: "left",
            124: "right",
            125: "down",
            126: "up",
        ]
        let namedPunctuation: [String: String] = [
            ",": "comma",
            ".": "period",
            "/": "slash",
            ";": "semicolon",
            "'": "quote",
            "[": "left-bracket",
            "]": "right-bracket",
            "\\": "backslash",
            "`": "backtick",
            "-": "minus",
            "=": "equal",
            "+": "plus",
        ]
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = Set<MyTTYKeyModifier>()
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        let key: String
        if let namedKey = keyCodeNames[event.keyCode] {
            key = namedKey
        } else {
            guard modifiers.contains(.command)
                    || modifiers.contains(.control)
                    || modifiers.contains(.option),
                  let characters = event.charactersIgnoringModifiers?.lowercased(),
                  characters.count == 1
            else { return nil }
            key = namedPunctuation[characters] ?? characters
        }
        self.init(key: key, modifiers: modifiers)
    }
}
