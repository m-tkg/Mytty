import Foundation
import MyTTYCore

enum TerminalCloseTarget: Equatable {
    case window
    case pane
    case tab
}

enum TerminalExitCloseAction: Equatable {
    case ignore
    case closePane(requiresConfirmation: Bool)
    case closeTab(requiresConfirmation: Bool)
    case closeLastPane

    static func make(
        processAlive: Bool,
        paneCount: Int,
        tabCount: Int
    ) -> Self {
        guard !processAlive else { return .ignore }
        if paneCount > 1 {
            return .closePane(requiresConfirmation: true)
        }
        if tabCount > 1 {
            return .closeTab(requiresConfirmation: true)
        }
        return .closeLastPane
    }
}

enum TerminalExitedSurfaceCloseResolution: Equatable {
    case close
    case restartSurface

    static func make(
        requiresConfirmation: Bool,
        confirmed: Bool
    ) -> Self {
        requiresConfirmation && !confirmed ? .restartSurface : .close
    }
}

enum TerminalPaneCloseAction: Equatable {
    case closePane
    case closeTab
    case closeLastPane

    static func make(paneCount: Int, tabCount: Int) -> Self {
        if paneCount > 1 { return .closePane }
        if tabCount > 1 { return .closeTab }
        return .closeLastPane
    }
}

/// Routes the Close Tab command (Cmd+W). `activeController` resolves to nil
/// when the key window is an auxiliary window (Settings, About) or when no
/// terminal windows exist at all, so the command must fall back to closing
/// the key window instead of silently doing nothing.
enum CloseTabCommandRouting: Equatable {
    case closeSelectedTab
    case closeKeyWindow
    case ignore

    static func make(
        hasActiveTerminalController: Bool,
        hasKeyWindow: Bool
    ) -> Self {
        // With no key window, `activeController` falls back to the first
        // terminal controller; closing its selected tab preserves the
        // behavior this command had before auxiliary-window routing.
        if hasActiveTerminalController { return .closeSelectedTab }
        return hasKeyWindow ? .closeKeyWindow : .ignore
    }
}

extension ApplicationPreferences {
    func confirmation(
        for target: TerminalCloseTarget
    ) -> CloseConfirmation {
        switch target {
        case .window:
            closeWindowConfirmation
        case .pane:
            closePaneConfirmation
        case .tab:
            closeTabConfirmation
        }
    }
}

enum ApplicationLaunchPolicy {
    static func sessionsToRestore(
        _ sessions: [WindowSession],
        behavior: LaunchBehavior
    ) -> [WindowSession] {
        switch behavior {
        case .restoreLastSession:
            sessions
        case .newWindow:
            []
        }
    }

    static func initialWorkingDirectory(
        homeDirectory: URL,
        processDirectory: URL
    ) -> URL {
        homeDirectory.isFileURL ? homeDirectory : processDirectory
    }
}

final class ApplicationTerminationState {
    private var isTerminating = false

    var shouldSaveAfterWindowRemoval: Bool {
        !isTerminating
    }

    func beginTermination() -> Bool {
        guard !isTerminating else { return false }
        isTerminating = true
        return true
    }
}

struct WindowStartupPlan: Equatable {
    let frame: WindowFrame

    static func make(
        behavior: WindowStartupBehavior,
        rememberedFrame: WindowFrame?,
        fallbackFrame: WindowFrame,
        maximumFrame: WindowFrame
    ) -> Self {
        switch behavior {
        case .rememberLastSize:
            Self(
                frame: centeredFrame(
                    width: rememberedFrame?.width ?? fallbackFrame.width,
                    height: rememberedFrame?.height ?? fallbackFrame.height,
                    within: maximumFrame
                )
            )
        case .fullscreen:
            Self(frame: maximumFrame)
        case .small:
            Self(
                frame: centeredFrame(
                    width: 820,
                    height: 520,
                    within: maximumFrame
                )
            )
        }
    }

    private static func centeredFrame(
        width: Double,
        height: Double,
        within bounds: WindowFrame
    ) -> WindowFrame {
        WindowFrame(
            x: bounds.x + (bounds.width - width) / 2,
            y: bounds.y + (bounds.height - height) / 2,
            width: width,
            height: height
        )
    }
}
