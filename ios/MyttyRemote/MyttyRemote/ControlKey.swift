import Foundation

enum ControlKey: String, CaseIterable, Identifiable {
    case escape, tab, shiftTab, paste, shift, control, option, command
    case `return`, delete
    case up, down, left, right
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    var id: String { rawValue }

    /// Keys shown in the on-screen bar. Return and delete are omitted:
    /// the software keyboard's own return and backspace keys already
    /// deliver those keystrokes directly.
    static let barKeys: [ControlKey] = allCases.filter {
        $0 != .return && $0 != .delete
    }

    var isModifier: Bool {
        switch self {
        case .shift, .control, .option, .command: true
        default: false
        }
    }

    var symbolName: String? {
        switch self {
        case .escape: "escape"
        case .tab: "arrow.right.to.line"
        case .shiftTab: "arrow.left.to.line"
        case .paste: "doc.on.clipboard"
        case .shift: "shift"
        case .control: "control"
        case .option: "option"
        case .command: "command"
        case .return: "return"
        case .delete: "delete.left"
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        default: nil
        }
    }

    /// Used for keys with no dedicated SF Symbol (the function keys),
    /// rendered inside a keycap-style badge instead.
    var label: String {
        switch self {
        case .f1: "F1"
        case .f2: "F2"
        case .f3: "F3"
        case .f4: "F4"
        case .f5: "F5"
        case .f6: "F6"
        case .f7: "F7"
        case .f8: "F8"
        case .f9: "F9"
        case .f10: "F10"
        case .f11: "F11"
        case .f12: "F12"
        default: ""
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .escape: "Escape"
        case .tab: "Tab"
        case .shiftTab: "Shift Tab"
        case .paste: "Paste"
        case .shift: "Shift"
        case .control: "Control"
        case .option: "Option"
        case .command: "Command"
        case .return: "Return"
        case .delete: "Delete"
        case .up: "Up arrow"
        case .down: "Down arrow"
        case .left: "Left arrow"
        case .right: "Right arrow"
        default: label
        }
    }
}
