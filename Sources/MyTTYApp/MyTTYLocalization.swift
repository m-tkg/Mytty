import Foundation
import MyTTYCore

enum ResolvedAppLanguage: Equatable {
    case english
    case japanese

    /// Maps to MyTTYCore's `PaneTeamPointerLanguage` -- MyTTYCore only
    /// receives an already-resolved language (never `.systemDefault`), so
    /// callers writing or previewing the pane-team pointer convert through
    /// here rather than resolving the system locale themselves.
    var paneTeamPointerLanguage: PaneTeamPointerLanguage {
        switch self {
        case .english: .english
        case .japanese: .japanese
        }
    }
}

extension AppLanguage {
    func resolved(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> ResolvedAppLanguage {
        switch self {
        case .english:
            .english
        case .japanese:
            .japanese
        case .systemDefault:
            preferredLanguages.first.map {
                $0.lowercased().hasPrefix("ja")
            } == true ? .japanese : .english
        }
    }
}

enum MyTTYText: String {
    case general = "General"
    case window = "Window"
    case terminal = "Terminal"
    case autocomplete = "Autocomplete"
    case keyBindings = "Key Bindings"
    case agents = "Agents"
    case language = "Language"
    case onLaunch = "On Launch"
    case systemDefault = "System default"
    case english = "English"
    case japanese = "Japanese"
    case restoreLastSession = "Restore last session"
    case newWindow = "New Window"
    case tabs = "Tabs"
    case position = "Position"
    case left = "Left"
    case right = "Right"
    case top = "Top"
    case bottom = "Bottom"
    case newTabPosition = "New Tab Position"
    case newTabPositionEnd = "At the End"
    case newTabPositionAfterCurrent = "After Current Tab"
    case mode = "Mode"
    case rememberLastSize = "Remember last size"
    case fullscreen = "Fullscreen"
    case small = "Small"
    case statusBar = "Status Bar"
    case confirmation = "Confirmation"
    case closeWindow = "Close Window"
    case minimizeWindow = "Minimize"
    case zoomWindow = "Zoom"
    case bringAllToFront = "Bring All to Front"
    case closePane = "Close Pane"
    case closeTab = "Close Tab"
    case reopenClosedItem = "Reopen Closed Item"
    case recentlyClosedItems = "Recently Closed Items"
    case noRecentlyClosedItems = "No Recently Closed Items"
    case closeLastPane = "Close Last Pane"
    case whenProcessRunning = "When a process is running"
    case always = "Always"
    case font = "Font"
    case family = "Family"
    case size = "Size"
    case appearance = "Appearance"
    case theme = "Theme"
    case customColors = "Custom Colors"
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    case text = "Text"
    case background = "Background"
    case backgroundOpacity = "Background opacity"
    case inactivePaneDimming = "Inactive pane dimming"
    case activePaneBorder = "Active pane border"
    case activePaneBorderColor = "Border color"
    case activePaneBorderWidth = "Border width"
    case cursor = "Cursor"
    case shape = "Shape"
    case block = "Block"
    case bar = "Bar"
    case underline = "Underline"
    case blink = "Blink"
    case terminalDefault = "Terminal default"
    case on = "On"
    case off = "Off"
    case shell = "Shell"
    case defaultLoginShell = "Default login shell"
    case application = "Application"
    case defaultTerminal = "Default Terminal"
    case makeDefaultTerminal = "Make Mytty Default"
    case defaultTerminalActive = "Mytty is the default terminal."
    case defaultTerminalRegistrationFailed = "Mytty could not be set as the default terminal."
    case commandLineTool = "Command Line Tool"
    case installCommandLineTool = "Install CLI"
    case commandLineToolInstalled = "%@ is on your PATH."
    case commandLineToolConflict = "Something else already exists at ~/.local/bin/%@. Remove it, then try again."
    case commandLineToolInstallFailed = "Couldn't install %@."
    case commandLineToolPathHint = "~/.local/bin isn't on your PATH yet. Add this to your shell profile: %@"
    case panes = "Panes"
    case attention = "Attention"
    case ago = "ago"
    case moveToShell = "Move to the shell"
    case scheduledInput = "Scheduled Input"
    case newScheduledInput = "New Scheduled Input"
    case scheduled = "Scheduled"
    case dateAndTime = "Date and time"
    case inputText = "Input text"
    case appendNewline = "Append newline"
    case restoreDefault = "Restore Default"
    case notSet = "Not Set"
    case recording = "Recording..."
    case file = "File"
    case pane = "Pane"
    case view = "View"
    case settings = "Settings"
    case updates = "Updates"
    case aboutMyTTY = "About Mytty"
    case currentVersion = "Current Version"
    case sessionID = "Session ID"
    case copySessionID = "Copy Session ID"
    case context = "Context"
    case copy = "Copy"
    case cut = "Cut"
    case paste = "Paste"
    case selectAll = "Select All"
    case lookUpSelectionFormat = "Look Up “%@”"
    case searchWithGoogle = "Search with Google"
    case share = "Share"
    case services = "Services"
    case preventSleepWhileAgentRunning = "Prevent Mac sleep for agents"
    case preventSleepWhileAgentRunningDescription = "Choose when Mytty keeps this Mac awake for agents."
    case attentionUnreadOnly = "Show unread only"
    case attentionUnreadOnlyDescription = "Hide resolved and acknowledged items from the Attention list."
    case teachPaneTeamPointers = "Teach agents about Mytty orchestration"
    case teachPaneTeamPointersDescription = "For Claude Code and Codex, add a short reference to the bundled usage guide (mytty-ctl.md) when asked to run sub-agents across panes."
    case orchestration = "Orchestration"
    case orchestrationOverviewDescription = "Any agent running in a Mytty pane can drive mytty-ctl to open another pane, launch a second agent in it, and work with it as a team. No background process is required. This section gathers the pieces that setup needs: the CLI, the note that teaches an agent to find it, and how to actually ask for it."
    case orchestrationCommandLineToolDescriptionFormat = "A symlink to mytty-ctl, placed at ~/.local/bin/%@. Panes Mytty opens already have it on PATH, so this only matters for calling mytty-ctl from outside Mytty: another terminal app or a script."
    case orchestrationPointerTargetsHeading = "Target files"
    case orchestrationPointerGuideMarkdownFormat = "Both files below just point at the guide Mytty writes and keeps up to date at %@."
    case orchestrationPointerPreviewButton = "Show what will be written"
    case orchestrationExamplesHeading = "How to ask for it"
    case orchestrationExampleGuidanceOnCLIInstalledLabel = "Guidance on, CLI installed"
    case orchestrationExampleGuidanceOnCLINotInstalledLabel = "Guidance on, CLI not installed"
    case orchestrationExampleGuidanceOffLabel = "Guidance off"
    case orchestrationExampleCLINote = "Inside a Mytty pane, mytty-ctl is already on PATH either way, so these two read the same. Installing the CLI to PATH only matters outside Mytty."
    case orchestrationExampleCurrentBadge = "Matches your current setting"
    case orchestrationExamplePromptGuided = "Split the pane and have Claude Code review this diff in parallel."
    case orchestrationExamplePromptUnguided = "Run \"mytty-ctl guide\" first, then split the pane and have Claude Code review this diff in parallel."
    case sleepClamshellArmedStatus =
        "sleep is disabled even with the lid closed"
    case sleepClamshellApprovalStatus =
        "allow Mytty's background item in System Settings to keep the Mac awake with the lid closed"
    case sleepModeAllowSleep = "Allow sleep"
    case sleepModePreventWhileProcessing = "Prevent while agent is running"
    case sleepModePreventWhileLaunched = "Prevent while agent is open"
    case sleepPreventionDisabled = "Agent sleep prevention off"
    case sleepPreventionEnabled = "Agent sleep prevention on"
    case sleepPrevented = "Sleep prevented"
    case sleepPreventionArmedWhileLaunched = "Agent sleep prevention on (while open)"
    case sleepPreventingWhileLaunched = "Sleep prevented (agent open)"
    case checkForUpdates = "Check for Updates"
    case checkForUpdatesPrereleaseHint = "Option-click to also check pre-releases"
    case update = "Update"
    case checkingForUpdates = "Checking for updates..."
    case upToDate = "Mytty is up to date."
    case updateAvailableFormat = "Mytty %@ is available."
    case installingUpdate = "Downloading and verifying the update..."
    case updateCheckFailed = "Could not check for updates."
    case updateInstallFailed = "Could not install the update."
    case updateInstalled = "Update installed. Restarting Mytty..."
    case installUpdateQuestion = "Install update?"
    case restartForUpdateWarning = "Mytty will restart. Running terminal processes will be closed."
    case search = "Search"
    case noMatchingSettings = "No matching settings"
    case quitMyTTY = "Quit Mytty"
    case nextTab = "Next Tab"
    case previousTab = "Previous Tab"
    case nextWindow = "Next Window"
    case previousWindow = "Previous Window"
    case newTab = "New Tab"
    case openHTMLFile = "Open HTML File"
    case renameTab = "Rename Tab"
    case splitLeft = "Split Left"
    case splitRight = "Split Right"
    case splitUp = "Split Up"
    case splitDown = "Split Down"
    case focusLeft = "Focus Left"
    case focusRight = "Focus Right"
    case focusUp = "Focus Up"
    case focusDown = "Focus Down"
    case equalizePanes = "Equalize Panes"
    case togglePaneZoom = "Toggle Pane Zoom"
    case swapPanes = "Swap Panes"
    case selectPaneToSwap = "Select a pane to swap"
    case selectSecondPaneToSwap = "Select the second pane to swap"
    case findInPane = "Find in Pane"
    case reloadBrowserPage = "Reload Page"
    case showPaneList = "Show All Panes"
    case focusPane = "Focus Pane"
    case noPanes = "No panes are open."
    case command = "Command"
    case workingDirectory = "CWD"
    case previousMatch = "Previous match"
    case nextMatch = "Next match"
    case closeSearch = "Close search"
    case matchFound = "Match"
    case noMatches = "No matches"
    case paneZoomed = "Focused pane is zoomed"
    case toggleAttention = "Toggle Attention"
    case clearAllAttention = "Clear All"
    case toggleTabPanel = "Toggle Tab Panels"
    case tabName = "Tab name"
    case autoNameTab = "Auto-Name"
    case showTabUptime = "Show Elapsed Time in Tabs"
    case tabUptime = "Elapsed Time"
    case explainPane = "Explain Pane"
    case edit = "Edit"
    case composeOneLiner = "Compose One-Liner"
    case oneLinerRequestPlaceholder = "Describe what you want to do"
    case generate = "Generate"
    case oneLinerGenerating = "Generating…"
    case oneLinerFailed = "Could not generate a command."
    case summarizeLastCommand = "Summarize Last Command"
    case commandSummaryAnalyzing = "Summarizing the last command…"
    case paneExplanationAnalyzing = "Analyzing the pane…"
    case paneExplanationUnavailable =
        "The on-device model is not available."
    case paneExplanationFailed = "Could not generate an explanation."
    case save = "Save"
    case copyPath = "Copy path"
    case revealInFinder = "Reveal in Finder"
    case openOnGitHub = "Open on GitHub"
    case terminalRecording = "Recording"
    case toggleRecording = "Start/Stop Recording"
    case commandPalette = "Command Palette"
    case sleepClamshellApprovalPromptTitle =
        "Keep the Mac awake with the lid closed?"
    case sleepClamshellApprovalPromptMessage =
        "While sleep prevention is active, Mytty can also stop the forced sleep that closing the lid causes. This uses a bundled helper that must be allowed once as a background item in System Settings (Touch ID or your password may be requested). Open System Settings now?"
    case openSystemSettings = "Open System Settings"
    case sleepClamshellRegistrationFailed =
        "the lid-closed keep-awake helper could not be registered — make sure Mytty is in /Applications"
    case notNow = "Not Now"
    case commandPaletteSearchPlaceholder = "Type a command name"
    case commandPaletteNoResults = "No matching commands"
    case showPressedKeysInPane = "Show pressed keys below cursor"
    case inlineSuggestions = "Inline Suggestions"
    case acceptSuggestion = "Accept Suggestion"
    case tabKey = "Tab"
    case stopRecording = "Stop Recording"
    case moveUp = "Move up"
    case moveDown = "Move down"
    case reorderTab = "Reorder Tab"
    case browser = "Browser"
    case openInBrowser = "Open in browser"
    case openInNewTab = "Open in new tab"
    case openInNewPaneRight = "Open in new pane (right)"
    case openInNewPaneDown = "Open in new pane (down)"
    case copyLink = "Copy link"
    case paneActions = "Pane Actions"
    case paneProcesses = "Running Processes"
    case agentIntegrations = "Agent Integrations"
    case notInstalled = "Not installed"
    case installed = "Installed"
    case needsRepair = "Needs repair"
    case repairIntegration = "Repair Integration"
    case installIntegration = "Install Integration"
    case removeIntegration = "Remove Integration"
    case noItemsNeedAttention = "No items need attention"
    case resolved = "Resolved"
    case focusTerminal = "Focus Terminal"
    case acknowledge = "Acknowledge"
    case closeAttention = "Close Attention"
    case unknown = "Unknown"
    case running = "Running"
    case input = "Input"
    case approval = "Approval"
    case done = "Done"
    case failed = "Failed"
    case offline = "Offline"
    case approvalRequested = "Approval requested"
    case inputRequested = "Input requested"
    case agentFailed = "Agent failed"
    case agentDisconnected = "Agent disconnected"
    case workCompleted = "Work completed"
    case approvalFallback = "Review the approval request in the terminal."
    case inputFallback = "The agent is waiting for input in the terminal."
    case failureFallback = "The agent stopped with an error."
    case disconnectedFallback = "The agent event connection was lost."
    case completionFallback = "Long-running work completed successfully."
    case closeWindowQuestion = "Close window?"
    case closePaneQuestion = "Close pane?"
    case closeTabQuestion = "Close tab?"
    case closeLastPaneQuestion = "Close the last pane?"
    case closeLastPaneWarning = "This will close all tabs in this window."
    case runningProcessWarning = "A process is still running in this terminal."
    case close = "Close"
    case closeBrowser = "Close Browser"
    case browserLoadFailed = "Failed to load page"
    case cancel = "Cancel"
    case myTTYSettings = "Mytty Settings"
    case couldNotStart = "Mytty could not start"
    case couldNotCompleteAction = "Mytty could not complete the action"
    case unableToReadSettings = "Unable to read settings"
    case unableToSaveSettings = "Unable to save application settings"
    case unableToApplyTerminalSettings = "Unable to apply terminal settings"
    case hookHelperUnavailable = "Hook helper is unavailable"
    case invalidProviderConfiguration = "Provider configuration is not valid JSON"
    case unableToUpdateIntegration = "Unable to update integration"
    case codexTrustGuidance = "Restart Codex, then run /hooks. Open each event, select mytty-agent-hook, and approve it if needed until Trust says Trusted."
    case remote = "iOS Remote Access"
    case enableRemoteAccess = "Enable iOS Remote Access"
    case remoteAccessDescription = "Let the Mytty iOS app view and type into panes over your local network."
    case generatePairingCode = "Generate Pairing Code"
    case pairingCode = "Pairing Code"
    case cancelPairing = "Cancel Pairing"
    case pairingCodeInstructions = "Enter this code in the Mytty iOS app within 2 minutes."
    case pairingCodeExpired = "This code has expired. Generate a new one."
    case listeningPort = "Port"
    case pairedDevices = "Paired Devices"
    case noPairedDevices = "No devices are paired yet."
    case deviceName = "Device name"
    case renameDevice = "Rename"
    case renameDeviceQuestion = "Rename this device?"
    case removeDevice = "Remove"
    case removeDeviceQuestion = "Remove this device?"
    case removeDeviceWarning = "The iOS app will need to be paired again to reconnect."
    case iosRemoteConnected = "iOS device connected"
    case iosRemoteNotConnected = "No iOS device connected"
    case pushNotifications = "Push Notifications"
    case enablePushNotifications = "Send Attention alerts to iOS"
    case pushNotificationsDescription = "Alert paired iPhones when an agent needs you and the Mac is not in use, even if the Mytty app is closed. Alert text is encrypted with the pairing key before it leaves this Mac."
    case devicePushRegistered = "Push registered"
    case devicePushNotRegistered = "Push not registered"
}

struct MyTTYLocalizer: Equatable {
    let language: ResolvedAppLanguage

    init(
        language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.language = language.resolved(
            preferredLanguages: preferredLanguages
        )
    }

    subscript(key: MyTTYText) -> String {
        switch language {
        case .english:
            key.rawValue
        case .japanese:
            japanese(key)
        }
    }

    func commandTitle(_ command: MyTTYCommand) -> String {
        if let tabNumber = command.tabNumber {
            return goToTab(tabNumber)
        }
        guard let textKey = command.textKey else { return "" }
        return self[textKey]
    }

    func goToTab(_ number: Int) -> String {
        switch language {
        case .english: "Go to Tab \(number)"
        case .japanese: "タブ \(number) に移動"
        }
    }

    func paneCount(_ count: Int) -> String {
        switch language {
        case .english: "\(count) panes"
        case .japanese: "\(count) ペイン"
        }
    }

    func pairingCodeExpiresIn(seconds: Int) -> String {
        switch language {
        case .english: "Expires in \(seconds)s"
        case .japanese: "残り\(seconds)秒で失効"
        }
    }

    func listeningOnPort(_ port: Int) -> String {
        switch language {
        case .english: "Listening on port \(port)"
        case .japanese: "ポート \(port) で待受中"
        }
    }

    func pairedOnDate(_ date: String) -> String {
        switch language {
        case .english: "Paired \(date)"
        case .japanese: "\(date) にペアリング"
        }
    }

    func attentionCount(_ count: Int) -> String {
        switch language {
        case .english: "\(count) items need attention"
        case .japanese: "通知 \(count) 件"
        }
    }

    func remainingPercent(_ percent: Int) -> String {
        switch language {
        case .english: "\(percent)% left"
        case .japanese: "残り\(percent)%"
        }
    }

    func cachedUsageNote() -> String {
        switch language {
        case .english: "cached"
        case .japanese: "キャッシュ"
        }
    }

    func closeTitle(_ title: String) -> String {
        switch language {
        case .english: "Close \(title)"
        case .japanese: "\(title) を閉じる"
        }
    }

    func conflicts(with titles: [String]) -> String {
        switch language {
        case .english: "Conflicts with " + titles.joined(separator: ", ")
        case .japanese: titles.joined(separator: "、") + " と競合"
        }
    }

    func keyBindingLabel(for title: String) -> String {
        switch language {
        case .english: "\(title) key binding"
        case .japanese: "\(title) のキーバインド"
        }
    }

    func repairIntegration(_ provider: String) -> String {
        switch language {
        case .english: "Repair \(provider)"
        case .japanese: "\(provider) 連携を修復"
        }
    }

    func providerIntegration(_ provider: String) -> String {
        switch language {
        case .english: "\(provider) Integration"
        case .japanese: "\(provider) 連携"
        }
    }

    func toolRequiresApproval(_ toolName: String) -> String {
        switch language {
        case .english: "\(toolName) requires approval"
        case .japanese: "\(toolName) の承認が必要です"
        }
    }

    func toolRequestsInput(_ toolName: String) -> String {
        switch language {
        case .english: "\(toolName) requests input"
        case .japanese: "\(toolName) が入力を求めています"
        }
    }

    private func japanese(_ key: MyTTYText) -> String {
        switch key {
        case .general: "一般"
        case .window: "ウィンドウ"
        case .terminal: "ターミナル"
        case .autocomplete: "オートコンプリート"
        case .keyBindings: "キーバインド"
        case .agents: "Agent"
        case .language: "言語"
        case .onLaunch: "起動時"
        case .systemDefault: "システム設定"
        case .english: "英語"
        case .japanese: "日本語"
        case .restoreLastSession: "前回のセッションを復元"
        case .newWindow: "新規ウィンドウ"
        case .tabs: "タブ"
        case .position: "位置"
        case .left: "左"
        case .right: "右"
        case .top: "上"
        case .bottom: "下"
        case .newTabPosition: "新規タブの位置"
        case .newTabPositionEnd: "末尾"
        case .newTabPositionAfterCurrent: "現在のタブの次"
        case .mode: "モード"
        case .rememberLastSize: "前回のサイズを記憶"
        case .fullscreen: "フルスクリーン"
        case .small: "小"
        case .statusBar: "ステータスバー"
        case .confirmation: "終了確認"
        case .closeWindow: "ウィンドウを閉じる"
        case .minimizeWindow: "しまう"
        case .zoomWindow: "拡大/縮小"
        case .bringAllToFront: "すべてを手前に移動"
        case .closePane: "ペインを閉じる"
        case .closeTab: "タブを閉じる"
        case .reopenClosedItem: "閉じた項目を開き直す"
        case .recentlyClosedItems: "最近閉じた項目"
        case .noRecentlyClosedItems: "最近閉じた項目はありません"
        case .closeLastPane: "最後のペインを閉じる"
        case .whenProcessRunning: "プロセス実行中のみ"
        case .always: "常に確認"
        case .font: "フォント"
        case .family: "フォントファミリー"
        case .size: "サイズ"
        case .appearance: "外観"
        case .theme: "テーマ"
        case .customColors: "カスタムカラー"
        case .system: "システム"
        case .light: "ライト"
        case .dark: "ダーク"
        case .text: "文字色"
        case .background: "背景色"
        case .backgroundOpacity: "背景の透明度"
        case .inactivePaneDimming: "非アクティブペインの暗さ"
        case .activePaneBorder: "アクティブペインの枠線"
        case .activePaneBorderColor: "枠線の色"
        case .activePaneBorderWidth: "枠線の太さ"
        case .cursor: "カーソル"
        case .shape: "形状"
        case .block: "ブロック"
        case .bar: "バー"
        case .underline: "下線"
        case .blink: "点滅"
        case .terminalDefault: "ターミナルの既定値"
        case .on: "オン"
        case .off: "オフ"
        case .shell: "シェル"
        case .defaultLoginShell: "既定のログインシェル"
        case .application: "アプリケーション"
        case .defaultTerminal: "デフォルトターミナル"
        case .makeDefaultTerminal: "Mytty をデフォルトにする"
        case .defaultTerminalActive: "Mytty はデフォルトターミナルです。"
        case .defaultTerminalRegistrationFailed: "Mytty をデフォルトターミナルに設定できませんでした。"
        case .commandLineTool: "コマンドラインツール"
        case .installCommandLineTool: "CLI をインストール"
        case .commandLineToolInstalled: "%@ が PATH に追加されています。"
        case .commandLineToolConflict: "~/.local/bin/%@ に別のものが存在します。削除してからもう一度お試しください。"
        case .commandLineToolInstallFailed: "%@ をインストールできませんでした。"
        case .commandLineToolPathHint: "~/.local/bin がまだ PATH に含まれていません。シェルの設定ファイルに次の行を追加してください: %@"
        case .panes: "ペイン"
        case .attention: "通知"
        case .ago: "前"
        case .moveToShell: "シェルへ移動"
        case .scheduledInput: "日時指定入力"
        case .newScheduledInput: "新規"
        case .scheduled: "設定済"
        case .dateAndTime: "日時"
        case .inputText: "文字列"
        case .appendNewline: "改行を追加"
        case .restoreDefault: "既定値に戻す"
        case .notSet: "未設定"
        case .recording: "入力キー表示"
        case .file: "ファイル"
        case .pane: "ペイン"
        case .view: "表示"
        case .settings: "設定"
        case .updates: "アップデート"
        case .aboutMyTTY: "Mytty について"
        case .currentVersion: "現在のバージョン"
        case .sessionID: "セッション ID"
        case .copySessionID: "セッション ID をコピー"
        case .context: "コンテキスト"
        case .copy: "コピー"
        case .cut: "カット"
        case .paste: "ペースト"
        case .selectAll: "すべてを選択"
        case .lookUpSelectionFormat: "“%@”を調べる"
        case .searchWithGoogle: "Google で検索"
        case .share: "共有"
        case .services: "サービス"
        case .preventSleepWhileAgentRunning: "Agent 使用中のスリープ防止"
        case .preventSleepWhileAgentRunningDescription: "Agent 実行時、Mac のスリープを防ぐか選択します。"
        case .attentionUnreadOnly: "未読のみ表示"
        case .attentionUnreadOnlyDescription: "解決済み・既読の項目を Attention 一覧から非表示にします。"
        case .teachPaneTeamPointers: "Agent に Mytty オーケストレーションの使い方を教える"
        case .teachPaneTeamPointersDescription: "Claude Code と Codex に、複数ペインでサブエージェントを動かす際は同梱の使い方ガイド (mytty-ctl.md) への短い参照を追加します。"
        case .orchestration: "オーケストレーション"
        case .orchestrationOverviewDescription: "ペインで動いている Agent は mytty-ctl を使って別のペインを開き、そこに別の Agent を起動してチームとして動かせます。常駐プロセスは不要です。このセクションには、そのために必要なもの(CLI、それを見つけさせる案内、実際の呼び出し方)をまとめています。"
        case .orchestrationCommandLineToolDescriptionFormat: "mytty-ctl へのシンボリックリンクを ~/.local/bin/%@ に作成します。Mytty が開いたペインではすでに PATH が通っているため、これが必要なのは Mytty の外(別のターミナルアプリやスクリプト)から mytty-ctl を呼びたい場合だけです。"
        case .orchestrationPointerTargetsHeading: "対象ファイル"
        case .orchestrationPointerGuideMarkdownFormat: "以下のどちらのファイルも、Mytty が書き出して最新の状態に保つガイド (%@) を参照するだけです。"
        case .orchestrationPointerPreviewButton: "書き込む内容を表示"
        case .orchestrationExamplesHeading: "呼び出し方"
        case .orchestrationExampleGuidanceOnCLIInstalledLabel: "案内あり・CLI インストール済み"
        case .orchestrationExampleGuidanceOnCLINotInstalledLabel: "案内あり・CLI 未インストール"
        case .orchestrationExampleGuidanceOffLabel: "案内なし"
        case .orchestrationExampleCLINote: "Mytty のペイン内ではどちらの場合も mytty-ctl の PATH が通っているため、実際には同じ書き方になります。差が出るのは Mytty の外から使う場合だけです。"
        case .orchestrationExampleCurrentBadge: "現在の設定"
        case .orchestrationExamplePromptGuided: "ペインを分割して、この diff を Claude Code に並行でレビューさせて。"
        case .orchestrationExamplePromptUnguided: "まず「mytty-ctl guide」を実行してから、ペインを分割してこの diff を Claude Code に並行でレビューさせて。"
        case .sleepClamshellArmedStatus: "モニタを閉じてもスリープしません"
        case .sleepClamshellApprovalStatus:
            "システム設定で Mytty のバックグラウンド項目を許可するとモニタを閉じてもスリープしなくなります"
        case .sleepModeAllowSleep: "スリープする"
        case .sleepModePreventWhileProcessing: "Agent の実行中はスリープしない"
        case .sleepModePreventWhileLaunched: "Agent の起動中はスリープしない"
        case .sleepPreventionDisabled: "Agent スリープ抑止 OFF"
        case .sleepPreventionEnabled: "Agent スリープ抑止 ON"
        case .sleepPrevented: "スリープを抑止中"
        case .sleepPreventionArmedWhileLaunched: "Agent スリープ抑止 ON(起動中)"
        case .sleepPreventingWhileLaunched: "スリープを抑止中(Agent 起動中)"
        case .checkForUpdates: "アップデートを確認"
        case .checkForUpdatesPrereleaseHint: "option を押しながらクリックすると pre-release も確認"
        case .update: "アップデート"
        case .checkingForUpdates: "アップデートを確認中..."
        case .upToDate: "Mytty は最新です。"
        case .updateAvailableFormat: "Mytty %@ を利用できます。"
        case .installingUpdate: "アップデートをダウンロードして検証中..."
        case .updateCheckFailed: "アップデートを確認できませんでした。"
        case .updateInstallFailed: "アップデートをインストールできませんでした。"
        case .updateInstalled: "アップデートをインストールしました。Mytty を再起動します..."
        case .installUpdateQuestion: "アップデートをインストールしますか？"
        case .restartForUpdateWarning: "Mytty を再起動します。実行中のターミナルプロセスは終了します。"
        case .search: "検索"
        case .noMatchingSettings: "一致する設定がありません"
        case .quitMyTTY: "Mytty を終了"
        case .nextTab: "次のタブ"
        case .previousTab: "前のタブ"
        case .nextWindow: "次のウィンドウ"
        case .previousWindow: "前のウィンドウ"
        case .newTab: "新規タブ"
        case .openHTMLFile: "HTML ファイルを開く"
        case .renameTab: "タブ名を変更"
        case .autoNameTab: "自動で命名"
        case .showTabUptime: "タブに経過時間を表示"
        case .tabUptime: "経過時間"
        case .explainPane: "ペインを解説"
        case .edit: "編集"
        case .composeOneLiner: "ワンライナー作成"
        case .oneLinerRequestPlaceholder: "やりたいことを自然言語で入力"
        case .generate: "生成"
        case .oneLinerGenerating: "生成中…"
        case .oneLinerFailed: "コマンドを生成できませんでした。"
        case .summarizeLastCommand: "実行結果を要約"
        case .commandSummaryAnalyzing: "実行結果を要約中…"
        case .paneExplanationAnalyzing: "ペインを解析中…"
        case .paneExplanationUnavailable: "オンデバイスモデルを利用できません。"
        case .paneExplanationFailed: "解説を生成できませんでした。"
        case .splitLeft: "左に分割"
        case .splitRight: "右に分割"
        case .splitUp: "上に分割"
        case .splitDown: "下に分割"
        case .focusLeft: "左のペインへ移動"
        case .focusRight: "右のペインへ移動"
        case .focusUp: "上のペインへ移動"
        case .focusDown: "下のペインへ移動"
        case .equalizePanes: "ペインを均等にする"
        case .togglePaneZoom: "ペインズームを切り替え"
        case .swapPanes: "ペインを入れ替え"
        case .selectPaneToSwap: "入れ替えるペインを選択してください"
        case .selectSecondPaneToSwap: "入れ替えるもう一方のペインを選択してください"
        case .findInPane: "ペイン内を検索"
        case .reloadBrowserPage: "ページを再読み込み"
        case .showPaneList: "すべてのペインを表示"
        case .focusPane: "ペインへ移動"
        case .noPanes: "開いているペインはありません。"
        case .command: "コマンド"
        case .workingDirectory: "CWD"
        case .previousMatch: "前の一致"
        case .nextMatch: "次の一致"
        case .closeSearch: "検索を閉じる"
        case .matchFound: "一致"
        case .noMatches: "一致なし"
        case .paneZoomed: "現在のペインを全体表示中"
        case .toggleAttention: "通知を表示"
        case .clearAllAttention: "すべてクリア"
        case .toggleTabPanel: "タブパネルを表示／非表示"
        case .tabName: "タブ名"
        case .save: "保存"
        case .copyPath: "パスをコピー"
        case .revealInFinder: "Finder に表示"
        case .openOnGitHub: "GitHub で開く"
        case .terminalRecording: "録画"
        case .toggleRecording: "録画を開始／停止"
        case .commandPalette: "コマンドパレット"
        case .sleepClamshellApprovalPromptTitle:
            "モニタを閉じてもスリープしないようにしますか？"
        case .sleepClamshellApprovalPromptMessage:
            "スリープ防止が有効な間、モニタを閉じた時の強制スリープも Mytty が抑止できるようになります。そのためには、同梱ヘルパーをシステム設定のバックグラウンド項目として一度だけ許可する必要があります(Touch ID またはパスワードを求められる場合があります)。今すぐシステム設定を開きますか？"
        case .openSystemSettings: "システム設定を開く"
        case .sleepClamshellRegistrationFailed:
            "モニタクローズ抑止ヘルパーを登録できませんでした。Mytty が /Applications にあるか確認してください"
        case .notNow: "あとで"
        case .commandPaletteSearchPlaceholder: "コマンド名を入力"
        case .commandPaletteNoResults: "一致するコマンドがありません"
        case .showPressedKeysInPane: "押したキーをカーソルの下に表示"
        case .inlineSuggestions: "インライン候補"
        case .acceptSuggestion: "候補を確定"
        case .tabKey: "Tab"
        case .stopRecording: "録画を停止"
        case .moveUp: "上へ移動"
        case .moveDown: "下へ移動"
        case .reorderTab: "タブを並び替える"
        case .browser: "ブラウザ"
        case .openInBrowser: "ブラウザで開く"
        case .openInNewTab: "新規タブで開く"
        case .openInNewPaneRight: "右の新規ペインで開く"
        case .openInNewPaneDown: "下の新規ペインで開く"
        case .copyLink: "リンクをコピー"
        case .paneActions: "ペイン操作"
        case .paneProcesses: "実行中のプロセス"
        case .agentIntegrations: "Agent 連携"
        case .notInstalled: "未インストール"
        case .installed: "インストール済み"
        case .needsRepair: "修復が必要"
        case .repairIntegration: "連携を修復"
        case .installIntegration: "連携をインストール"
        case .removeIntegration: "連携を削除"
        case .noItemsNeedAttention: "通知はありません"
        case .resolved: "確認済"
        case .focusTerminal: "ターミナルを表示"
        case .acknowledge: "確認済みにする"
        case .closeAttention: "通知パネルを閉じる"
        case .unknown: "不明"
        case .running: "実行中"
        case .input: "入力待ち"
        case .approval: "承認待ち"
        case .done: "完了"
        case .failed: "失敗"
        case .offline: "切断"
        case .approvalRequested: "承認が必要です"
        case .inputRequested: "入力が必要です"
        case .agentFailed: "Agent が失敗しました"
        case .agentDisconnected: "Agent が切断されました"
        case .workCompleted: "処理が完了しました"
        case .approvalFallback: "ターミナルで承認リクエストを確認してください。"
        case .inputFallback: "Agent がターミナルでの入力を待っています。"
        case .failureFallback: "Agent がエラーで停止しました。"
        case .disconnectedFallback: "Agent との接続が切れました。"
        case .completionFallback: "長時間の処理が正常に完了しました。"
        case .closeWindowQuestion: "ウィンドウを閉じますか？"
        case .closePaneQuestion: "ペインを閉じますか？"
        case .closeTabQuestion: "タブを閉じますか？"
        case .closeLastPaneQuestion: "最後のペインを閉じますか？"
        case .closeLastPaneWarning: "このウィンドウのすべてのタブが閉じます。"
        case .runningProcessWarning: "このターミナルではプロセスが実行中です。"
        case .close: "閉じる"
        case .closeBrowser: "ブラウザを閉じる"
        case .browserLoadFailed: "ページを読み込めませんでした"
        case .cancel: "キャンセル"
        case .myTTYSettings: "Mytty 設定"
        case .couldNotStart: "Mytty を起動できませんでした"
        case .couldNotCompleteAction: "操作を完了できませんでした"
        case .unableToReadSettings: "設定を読み込めませんでした"
        case .unableToSaveSettings: "アプリ設定を保存できませんでした"
        case .unableToApplyTerminalSettings: "ターミナル設定を適用できませんでした"
        case .hookHelperUnavailable: "フックヘルパーを利用できません"
        case .invalidProviderConfiguration: "プロバイダー設定が正しい JSON ではありません"
        case .unableToUpdateIntegration: "Agent 連携を更新できませんでした"
        case .codexTrustGuidance: "Codex を再起動して /hooks を実行してください。各イベントで mytty-agent-hook を選択し、Trust が Trusted になるまで必要に応じて承認してください。"
        case .remote: "iOS リモートアクセス"
        case .enableRemoteAccess: "iOS リモートアクセスを有効にする"
        case .remoteAccessDescription: "同一ネットワーク上の Mytty iOS アプリからペインの内容を表示し、入力できるようにします。"
        case .generatePairingCode: "ペアリングコードを生成"
        case .pairingCode: "ペアリングコード"
        case .cancelPairing: "ペアリングをキャンセル"
        case .pairingCodeInstructions: "このコードを2分以内に Mytty iOS アプリに入力してください。"
        case .pairingCodeExpired: "このコードは失効しました。新しいコードを生成してください。"
        case .listeningPort: "ポート"
        case .pairedDevices: "ペアリング済みデバイス"
        case .noPairedDevices: "まだペアリングされたデバイスはありません。"
        case .deviceName: "デバイス名"
        case .renameDevice: "名前を変更"
        case .renameDeviceQuestion: "このデバイスの名前を変更しますか？"
        case .removeDevice: "削除"
        case .removeDeviceQuestion: "このデバイスを削除しますか？"
        case .removeDeviceWarning: "再接続するには iOS アプリで再度ペアリングが必要になります。"
        case .iosRemoteConnected: "iOS デバイスが接続中"
        case .iosRemoteNotConnected: "iOS デバイスは接続されていません"
        case .pushNotifications: "プッシュ通知"
        case .enablePushNotifications: "Attention を iOS に通知する"
        case .pushNotificationsDescription: "Agent が応答を待っていて Mac を操作していないとき、ペアリング済みの iPhone に通知します。Mytty アプリが終了していても届きます。本文はこの Mac を出る前にペアリング鍵で暗号化されます。"
        case .devicePushRegistered: "プッシュ登録済み"
        case .devicePushNotRegistered: "プッシュ未登録"
        }
    }
}

private extension MyTTYCommand {
    /// `nil` for `selectTab1`...`selectTab9`: those don't have a fixed
    /// `MyTTYText`, since their title embeds the tab number. `commandTitle`
    /// handles them via `tabNumber` before this is ever consulted.
    var textKey: MyTTYText? {
        switch self {
        case .settings: .settings
        case .quit: .quitMyTTY
        case .newWindow: .newWindow
        case .nextWindow: .nextWindow
        case .previousWindow: .previousWindow
        case .openHTML: .openHTMLFile
        case .newTab: .newTab
        case .renameTab: .renameTab
        case .closeTab: .closeTab
        case .reopenClosed: .reopenClosedItem
        case .nextTab: .nextTab
        case .previousTab: .previousTab
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
             .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            nil
        case .splitLeft: .splitLeft
        case .splitRight: .splitRight
        case .splitUp: .splitUp
        case .splitDown: .splitDown
        case .focusLeft: .focusLeft
        case .focusRight: .focusRight
        case .focusUp: .focusUp
        case .focusDown: .focusDown
        case .equalizePanes: .equalizePanes
        case .togglePaneZoom: .togglePaneZoom
        case .swapPanes: .swapPanes
        case .findInPane: .findInPane
        case .reloadBrowser: .reloadBrowserPage
        case .showPaneList: .showPaneList
        case .closePane: .closePane
        case .toggleTabPanel: .toggleTabPanel
        case .toggleRecording: .toggleRecording
        case .commandPalette: .commandPalette
        case .explainPane: .explainPane
        case .composeOneLiner: .composeOneLiner
        case .summarizeLastCommand: .summarizeLastCommand
        }
    }
}
