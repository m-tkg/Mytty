import MyTTYCore

struct KeyBindingCommandGroup {
    let title: MyTTYText
    let commands: [MyTTYCommand]
}

enum KeyBindingSettingsCatalog {
    static var groups: [KeyBindingCommandGroup] {
        var paneCommands: [MyTTYCommand] = [
            .showPaneList,
            .splitLeft,
            .splitRight,
            .splitUp,
            .splitDown,
            .focusLeft,
            .focusRight,
            .focusUp,
            .focusDown,
            .equalizePanes,
            .togglePaneZoom,
            .swapPanes,
            .findInPane,
            .closePane,
        ]
        var applicationCommands: [MyTTYCommand] = [
            .settings, .quit, .newWindow, .openHTML, .commandPalette,
        ]
        // The on-device model commands only exist as UI on macOS 26+
        // (Foundation Models), so their binding rows are hidden below
        // that.
        if #available(macOS 26, *) {
            paneCommands.append(.explainPane)
            paneCommands.append(.summarizeLastCommand)
            applicationCommands.append(.composeOneLiner)
        }
        return [
            KeyBindingCommandGroup(
                title: .application,
                commands: applicationCommands
            ),
            KeyBindingCommandGroup(
                title: .tabs,
                commands: [
                    .newTab,
                    .renameTab,
                    .closeTab,
                    .reopenClosed,
                    .toggleTabPanel,
                ]
            ),
            KeyBindingCommandGroup(
                title: .panes,
                commands: paneCommands
            ),
            KeyBindingCommandGroup(
                title: .terminalRecording,
                commands: [.toggleRecording]
            ),
        ]
    }
}
