import AppKit
import Foundation

struct TerminalAutocompleteSuggestion: Equatable, Sendable {
    let displayText: String
    let insertionText: String
}

enum TerminalAutocompleteInput: Equatable, Sendable {
    case text(String)
    case deleteBackward
    case submit
    case accept
    case cancel
    case resetLine
    case editingNavigation
}

enum TerminalAutocompleteAction: Equatable, Sendable {
    case hide
    case show(TerminalAutocompleteSuggestion)
    case insert(String)
}

@MainActor
enum TerminalAutocompleteEventMapper {
    static func input(
        for event: NSEvent,
        hasMarkedText: Bool
    ) -> TerminalAutocompleteInput? {
        if event.modifierFlags.contains(.command) {
            return nil
        }
        if hasMarkedText {
            return .cancel
        }
        if event.modifierFlags.contains(.control),
           event.keyCode == 8 || event.keyCode == 32 {
            return .resetLine
        }
        if !event.modifierFlags.intersection([.control, .option]).isEmpty {
            return .editingNavigation
        }

        switch event.keyCode {
        case 48:
            return .accept
        case 51:
            return .deleteBackward
        case 36, 76:
            return .submit
        case 53:
            return .cancel
        case 115, 116, 117, 119, 121, 123, 124, 125, 126:
            return .editingNavigation
        default:
            guard let characters = event.characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ scalar in
                      scalar.value >= 0x20
                          && scalar.value != 0x7F
                          && !(0xF700...0xF8FF).contains(scalar.value)
                  })
            else { return .editingNavigation }
            return .text(characters)
        }
    }
}

enum TerminalAutocompleteEngine {
    static func nextCommand(
        afterSuccessfulCommand command: String
    ) -> String? {
        let words = command.split(whereSeparator: \Character.isWhitespace)
        guard words.first == "mkdir" else { return nil }

        var operands: [Substring] = []
        var acceptsOptions = true
        for word in words.dropFirst() {
            if acceptsOptions, word == "--" {
                acceptsOptions = false
            } else if acceptsOptions, word.hasPrefix("-") {
                continue
            } else {
                operands.append(word)
            }
        }

        guard operands.count == 1,
              let path = operands.first,
              isSafeLiteralPath(path)
        else { return nil }
        return "cd \(path)"
    }

    private static func isSafeLiteralPath(_ value: Substring) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._~+-@%/=")
        )
        return !value.isEmpty && value.unicodeScalars.allSatisfy {
            allowed.contains($0)
        }
    }
}

struct TerminalAutocompleteSession {
    private(set) var currentInput = ""
    private(set) var successfulCommands: [String] = []

    private var pendingCommand: String?
    private var inputIsReliable = true
    private var suggestion: TerminalAutocompleteSuggestion?

    mutating func handle(
        _ input: TerminalAutocompleteInput
    ) -> TerminalAutocompleteAction {
        switch input {
        case let .text(text):
            suggestion = nil
            guard !text.isEmpty else { return .hide }
            currentInput.append(text)
            guard inputIsReliable,
                  let historySuggestion = historySuggestion()
            else { return .hide }
            suggestion = historySuggestion
            return .show(historySuggestion)

        case .deleteBackward:
            suggestion = nil
            guard inputIsReliable else { return .hide }
            if !currentInput.isEmpty {
                currentInput.removeLast()
            }
            guard let historySuggestion = historySuggestion() else {
                return .hide
            }
            suggestion = historySuggestion
            return .show(historySuggestion)

        case .submit:
            pendingCommand = inputIsReliable
                ? normalizedCommand(currentInput)
                : nil
            currentInput = ""
            inputIsReliable = true
            suggestion = nil
            return .hide

        case .accept:
            guard let suggestion else { return .hide }
            self.suggestion = nil
            currentInput.append(suggestion.insertionText)
            return .insert(suggestion.insertionText)

        case .cancel:
            inputIsReliable = false
            suggestion = nil
            return .hide

        case .resetLine:
            currentInput = ""
            pendingCommand = nil
            inputIsReliable = true
            suggestion = nil
            return .hide

        case .editingNavigation:
            inputIsReliable = false
            suggestion = nil
            return .hide
        }
    }

    mutating func commandFinished(
        exitCode: Int?,
        reportedCommand: String?
    ) -> TerminalAutocompleteAction {
        defer { pendingCommand = nil }
        guard exitCode == 0,
              let command = pendingCommand
                ?? normalizedCommand(reportedCommand ?? "")
        else {
            suggestion = nil
            return .hide
        }

        successfulCommands.removeAll { $0 == command }
        successfulCommands.append(command)
        if successfulCommands.count > 200 {
            successfulCommands.removeFirst(
                successfulCommands.count - 200
            )
        }

        guard let next = TerminalAutocompleteEngine.nextCommand(
            afterSuccessfulCommand: command
        ) else {
            suggestion = nil
            return .hide
        }
        let result = TerminalAutocompleteSuggestion(
            displayText: next,
            insertionText: next
        )
        suggestion = result
        return .show(result)
    }

    private func historySuggestion() -> TerminalAutocompleteSuggestion? {
        guard !currentInput.isEmpty,
              let match = successfulCommands.reversed().first(where: {
                  $0.count > currentInput.count && $0.hasPrefix(currentInput)
              })
        else { return nil }
        let suffix = String(match.dropFirst(currentInput.count))
        return TerminalAutocompleteSuggestion(
            displayText: suffix,
            insertionText: suffix
        )
    }

    private func normalizedCommand(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty,
              !result.contains(where: \Character.isNewline)
        else { return nil }
        return result
    }
}
