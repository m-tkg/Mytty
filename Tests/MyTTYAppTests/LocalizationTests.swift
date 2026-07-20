import MyTTYCore
import Testing

@testable import MyTTYApp

@Suite("Localization")
struct LocalizationTests {
    @Test("resolves explicit and system languages")
    func languageResolution() {
        #expect(
            AppLanguage.systemDefault.resolved(
                preferredLanguages: ["ja-JP", "en-US"]
            ) == .japanese
        )
        #expect(
            AppLanguage.systemDefault.resolved(
                preferredLanguages: ["en-JP", "ja-JP"]
            ) == .english
        )
        #expect(
            AppLanguage.english.resolved(
                preferredLanguages: ["ja-JP"]
            ) == .english
        )
        #expect(
            AppLanguage.japanese.resolved(
                preferredLanguages: ["en-US"]
            ) == .japanese
        )
    }

    @Test("provides English and Japanese application text")
    func localizedText() {
        let english = MyTTYLocalizer(language: .english)
        let japanese = MyTTYLocalizer(language: .japanese)

        #expect(english[.general] == "General")
        #expect(english[.keyBindings] == "Key Bindings")
        #expect(english[.window] == "Window")
        #expect(english[.right] == "Right")
        #expect(english[.bottom] == "Bottom")
        #expect(english[.restoreLastSession] == "Restore last session")
        #expect(english.commandTitle(.newWindow) == "New Window")
        #expect(english.commandTitle(.quit) == "Quit Mytty")
        #expect(english[.myTTYSettings] == "Mytty Settings")
        #expect(english[.couldNotStart] == "Mytty could not start")
        #expect(english[.closeBrowser] == "Close Browser")
        #expect(english[.statusBar] == "Status Bar")
        #expect(english[.inactivePaneDimming] == "Inactive pane dimming")
        #expect(english[.updates] == "Updates")
        #expect(english[.defaultTerminal] == "Default Terminal")
        #expect(english[.makeDefaultTerminal] == "Make Mytty Default")
        #expect(english[.defaultTerminalActive] == "Mytty is the default terminal.")
        #expect(english[.openOnGitHub] == "Open on GitHub")
        #expect(english[.copyLink] == "Copy link")
        #expect(english[.copy] == "Copy")
        #expect(english[.paste] == "Paste")
        #expect(english[.selectAll] == "Select All")
        #expect(english[.lookUpSelectionFormat] == "Look Up “%@”")
        #expect(english[.searchWithGoogle] == "Search with Google")
        #expect(english[.share] == "Share")
        #expect(english[.services] == "Services")
        #expect(english[.terminalRecording] == "Recording")
        #expect(english.commandTitle(.toggleRecording) == "Start/Stop Recording")
        #expect(
            english[.showPressedKeysInPane]
                == "Show pressed keys below cursor"
        )
        #expect(english[.stopRecording] == "Stop Recording")
        #expect(english[.autoNameTab] == "Auto-Name")
        #expect(japanese[.autoNameTab] == "自動で命名")
        #expect(english.commandTitle(.explainPane) == "Explain Pane")
        #expect(japanese[.explainPane] == "ペインを解説")
        #expect(japanese[.paneExplanationAnalyzing] == "ペインを解析中…")
        #expect(english.commandTitle(.composeOneLiner) == "Compose One-Liner")
        #expect(japanese[.composeOneLiner] == "ワンライナー作成")
        #expect(japanese[.edit] == "編集")
        #expect(japanese[.generate] == "生成")
        #expect(english[.clearAllAttention] == "Clear All")
        #expect(english.commandTitle(.reopenClosed) == "Reopen Closed Item")
        #expect(japanese.commandTitle(.reopenClosed) == "閉じた項目を開き直す")
        #expect(english[.recentlyClosedItems] == "Recently Closed Items")
        #expect(japanese[.recentlyClosedItems] == "最近閉じた項目")
        #expect(english[.noRecentlyClosedItems] == "No Recently Closed Items")
        #expect(japanese[.noRecentlyClosedItems] == "最近閉じた項目はありません")
        #expect(
            english.commandTitle(.summarizeLastCommand)
                == "Summarize Last Command"
        )
        #expect(japanese[.summarizeLastCommand] == "実行結果を要約")
        #expect(japanese[.commandSummaryAnalyzing] == "実行結果を要約中…")
        #expect(japanese[.clearAllAttention] == "すべてクリア")
        #expect(english[.aboutMyTTY] == "About Mytty")
        #expect(english[.sessionID] == "Session ID")
        #expect(english[.copySessionID] == "Copy Session ID")
        #expect(
            english[.preventSleepWhileAgentRunning]
                == "Prevent Mac sleep for agents"
        )
        #expect(
            english[.preventSleepWhileAgentRunningDescription]
                == "Choose when Mytty keeps this Mac awake for agents."
        )
        #expect(english[.sleepModeAllowSleep] == "Allow sleep")
        #expect(
            japanese[.sleepClamshellArmedStatus]
                == "モニタを閉じてもスリープしません"
        )
        #expect(
            japanese[.sleepClamshellApprovalStatus]
                == "システム設定で Mytty のバックグラウンド項目を許可するとモニタを閉じてもスリープしなくなります"
        )
        #expect(
            english[.sleepModePreventWhileProcessing]
                == "Prevent while agent is running"
        )
        #expect(
            english[.sleepModePreventWhileLaunched]
                == "Prevent while agent is open"
        )
        #expect(
            english[.sleepPreventionDisabled]
                == "Agent sleep prevention off"
        )
        #expect(
            english[.sleepPreventionEnabled]
                == "Agent sleep prevention on"
        )
        #expect(english[.sleepPrevented] == "Sleep prevented")
        #expect(
            english[.sleepPreventionArmedWhileLaunched]
                == "Agent sleep prevention on (while open)"
        )
        #expect(
            english[.sleepPreventingWhileLaunched]
                == "Sleep prevented (agent open)"
        )
        #expect(japanese[.sessionID] == "セッション ID")
        #expect(japanese[.copySessionID] == "セッション ID をコピー")
        #expect(
            japanese[.preventSleepWhileAgentRunning]
                == "Agent 使用中のスリープ防止"
        )
        #expect(
            japanese[.preventSleepWhileAgentRunningDescription]
                == "Agent 実行時、Mac のスリープを防ぐか選択します。"
        )
        #expect(japanese[.sleepModeAllowSleep] == "スリープする")
        #expect(
            japanese[.sleepModePreventWhileProcessing]
                == "Agent の実行中はスリープしない"
        )
        #expect(
            japanese[.sleepModePreventWhileLaunched]
                == "Agent の起動中はスリープしない"
        )
        #expect(
            japanese[.sleepPreventionDisabled]
                == "Agent スリープ抑止 OFF"
        )
        #expect(
            japanese[.sleepPreventionEnabled]
                == "Agent スリープ抑止 ON"
        )
        #expect(japanese[.sleepPrevented] == "スリープを抑止中")
        #expect(
            japanese[.sleepPreventionArmedWhileLaunched]
                == "Agent スリープ抑止 ON(起動中)"
        )
        #expect(
            japanese[.sleepPreventingWhileLaunched]
                == "スリープを抑止中(Agent 起動中)"
        )
        #expect(english[.checkForUpdates] == "Check for Updates")
        #expect(
            english[.checkForUpdatesPrereleaseHint]
                == "Option-click to also check pre-releases"
        )
        #expect(english[.update] == "Update")
        #expect(english[.ago] == "ago")
        #expect(english[.moveToShell] == "Move to the shell")
        #expect(english[.scheduledInput] == "Scheduled Input")
        #expect(english[.newScheduledInput] == "New Scheduled Input")
        #expect(english[.scheduled] == "Scheduled")
        #expect(english[.dateAndTime] == "Date and time")
        #expect(english[.appendNewline] == "Append newline")
        #expect(english.commandTitle(.togglePaneZoom) == "Toggle Pane Zoom")
        #expect(english.commandTitle(.findInPane) == "Find in Pane")
        #expect(english.commandTitle(.showPaneList) == "Show All Panes")
        #expect(english[.focusPane] == "Focus Pane")
        #expect(english[.noPanes] == "No panes are open.")
        #expect(english[.paneZoomed] == "Focused pane is zoomed")
        #expect(english.paneCount(3) == "3 panes")
        #expect(
            english[.hookHelperUnavailable]
                == "Hook helper is unavailable"
        )

        #expect(japanese[.general] == "一般")
        #expect(japanese[.window] == "ウィンドウ")
        #expect(japanese[.right] == "右")
        #expect(japanese[.bottom] == "下")
        #expect(japanese[.restoreLastSession] == "前回のセッションを復元")
        #expect(japanese.commandTitle(.newWindow) == "新規ウィンドウ")
        #expect(japanese.commandTitle(.quit) == "Mytty を終了")
        #expect(japanese[.myTTYSettings] == "Mytty 設定")
        #expect(japanese[.closeBrowser] == "ブラウザを閉じる")
        #expect(japanese[.statusBar] == "ステータスバー")
        #expect(japanese[.inactivePaneDimming] == "非アクティブペインの暗さ")
        #expect(japanese[.recording] == "入力キー表示")
        #expect(japanese[.confirmation] == "終了確認")
        #expect(japanese[.attention] == "通知")
        #expect(japanese[.toggleAttention] == "通知を表示")
        #expect(japanese.attentionCount(3) == "通知 3 件")
        #expect(japanese[.noItemsNeedAttention] == "通知はありません")
        #expect(japanese[.resolved] == "確認済")
        #expect(japanese[.closeAttention] == "通知パネルを閉じる")
        #expect(japanese[.input] == "入力待ち")
        #expect(japanese[.updates] == "アップデート")
        #expect(japanese[.defaultTerminal] == "デフォルトターミナル")
        #expect(japanese[.makeDefaultTerminal] == "Mytty をデフォルトにする")
        #expect(japanese[.defaultTerminalActive] == "Mytty はデフォルトターミナルです。")
        #expect(japanese[.openOnGitHub] == "GitHub で開く")
        #expect(japanese[.copyLink] == "リンクをコピー")
        #expect(japanese[.copy] == "コピー")
        #expect(japanese[.paste] == "ペースト")
        #expect(japanese[.selectAll] == "すべてを選択")
        #expect(japanese[.lookUpSelectionFormat] == "“%@”を調べる")
        #expect(japanese[.searchWithGoogle] == "Google で検索")
        #expect(japanese[.share] == "共有")
        #expect(japanese[.services] == "サービス")
        #expect(japanese[.terminalRecording] == "録画")
        #expect(japanese.commandTitle(.toggleRecording) == "録画を開始／停止")
        #expect(
            japanese[.showPressedKeysInPane]
                == "押したキーをカーソルの下に表示"
        )
        #expect(japanese[.stopRecording] == "録画を停止")
        #expect(japanese[.aboutMyTTY] == "Mytty について")
        #expect(japanese[.checkForUpdates] == "アップデートを確認")
        #expect(
            japanese[.checkForUpdatesPrereleaseHint]
                == "option を押しながらクリックすると pre-release も確認"
        )
        #expect(japanese[.update] == "アップデート")
        #expect(japanese[.ago] == "前")
        #expect(japanese[.moveToShell] == "シェルへ移動")
        #expect(japanese[.scheduledInput] == "日時指定入力")
        #expect(japanese[.newScheduledInput] == "新規")
        #expect(japanese[.scheduled] == "設定済")
        #expect(japanese[.dateAndTime] == "日時")
        #expect(japanese[.appendNewline] == "改行を追加")
        #expect(japanese.commandTitle(.togglePaneZoom) == "ペインズームを切り替え")
        #expect(japanese.commandTitle(.findInPane) == "ペイン内を検索")
        #expect(japanese.commandTitle(.showPaneList) == "すべてのペインを表示")
        #expect(japanese[.focusPane] == "ペインへ移動")
        #expect(japanese[.noPanes] == "開いているペインはありません。")
        #expect(japanese[.paneZoomed] == "現在のペインを全体表示中")
        #expect(japanese.paneCount(3) == "3 ペイン")
        #expect(
            japanese[.hookHelperUnavailable]
                == "フックヘルパーを利用できません"
        )
        #expect(
            japanese[.invalidProviderConfiguration]
                == "プロバイダー設定が正しい JSON ではありません"
        )
        #expect(
            japanese[.unableToUpdateIntegration]
                == "Agent 連携を更新できませんでした"
        )
    }
}
