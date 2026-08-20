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
        #expect(english[.enableIntegration] == "Enable Integration")
        #expect(japanese[.enableIntegration] == "連携を有効化")
        #expect(
            english.integrationEnablePromptTitle("Codex")
                == "Enable the Codex hook integration?"
        )
        #expect(
            japanese.integrationEnablePromptTitle("Codex")
                == "Codex の hook 連携を有効化しますか？"
        )
        #expect(
            english.integrationRepairPromptTitle("Codex, Cursor")
                .contains("Codex, Cursor")
        )
        #expect(
            japanese[.integrationInstallPromptMessage]
                .contains("mytty-ctl")
        )
        #expect(english[.bottom] == "Bottom")
        #expect(english[.restoreLastSession] == "Restore last session")
        #expect(english.commandTitle(.newWindow) == "New Window")
        #expect(english.commandTitle(.quit) == "Quit Mytty")
        #expect(english[.myTTYSettings] == "Mytty Settings")
        #expect(english[.couldNotStart] == "Mytty could not start")
        #expect(english[.closeBrowser] == "Close Browser")
        #expect(english[.browserLoadFailed] == "Failed to load page")
        #expect(english.commandTitle(.openURL) == "Open URL")
        #expect(english[.openAction] == "Open")
        #expect(japanese.commandTitle(.openURL) == "URL を開く")
        #expect(japanese[.openAction] == "開く")
        #expect(english[.statusBar] == "Status Bar")
        #expect(english[.inactivePaneDimming] == "Inactive pane dimming")
        #expect(english[.activePaneBorder] == "Active pane border")
        #expect(english[.activePaneBorderColor] == "Border color")
        #expect(english[.activePaneBorderWidth] == "Border width")
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
        #expect(english[.moveToTab] == "Move to Tab")
        #expect(english[.terminalRecording] == "Recording")
        #expect(english.commandTitle(.toggleRecording) == "Start/Stop Recording")
        #expect(
            english.commandTitle(.togglePressedKeyToast)
                == "Show/Hide Pressed Keys"
        )
        #expect(
            english[.showPressedKeysInPane]
                == "Show pressed keys below cursor"
        )
        #expect(english[.stopRecording] == "Stop Recording")
        #expect(english[.gifRecording] == "GIF Recording")
        #expect(japanese[.gifRecording] == "GIF 録画")
        #expect(
            english[.recordingCountdownEnabled]
                == "Countdown before recording"
        )
        #expect(
            japanese[.recordingCountdownEnabled] == "録画開始前にカウントダウン"
        )
        #expect(english[.recordingFadeOutAtEnd] == "Fade out at the end")
        #expect(japanese[.recordingFadeOutAtEnd] == "最後にフェードアウト")
        #expect(english[.recordingFadeOutColor] == "Fade-out color")
        #expect(japanese[.recordingFadeOutColor] == "フェードアウトの色")
        #expect(english[.recordingFadeOutDuration] == "Fade-out duration")
        #expect(japanese[.recordingFadeOutDuration] == "フェードアウトの時間")
        #expect(english[.newTabPosition] == "New Tab Position")
        #expect(japanese[.newTabPosition] == "新規タブの位置")
        #expect(english[.newTabPositionEnd] == "At the End")
        #expect(japanese[.newTabPositionEnd] == "末尾")
        #expect(english[.newTabPositionAfterCurrent] == "After Current Tab")
        #expect(japanese[.newTabPositionAfterCurrent] == "現在のタブの次")
        #expect(english[.showPaneStatusBar] == "Show a status bar in each pane")
        #expect(japanese[.showPaneStatusBar] == "各ペインにステータスバーを表示")
        #expect(
            english[.showPaneStatusBarNote]
                == "Only while a tab is split into two or more panes."
        )
        #expect(
            japanese[.showPaneStatusBarNote]
                == "タブが 2 ペイン以上に分割されているときだけ表示します。"
        )
        #expect(english[.branch] == "Branch")
        #expect(japanese[.branch] == "ブランチ")
        #expect(english[.showTabUptime] == "Show Elapsed Time in Tabs")
        #expect(japanese[.showTabUptime] == "タブに経過時間を表示")
        #expect(
            english[.autoNameAgentTabs]
                == "Auto-Name Tabs From Agent Conversations"
        )
        #expect(
            japanese[.autoNameAgentTabs] == "エージェントの会話からタブを自動命名"
        )
        #expect(english[.tabUptime] == "Elapsed Time")
        #expect(japanese[.tabUptime] == "経過時間")
        #expect(english[.autoNameTab] == "Auto-Name")
        #expect(japanese[.autoNameTab] == "自動で命名")
        #expect(english.commandTitle(.explainPane) == "Explain Pane")
        #expect(japanese[.explainPane] == "ペインを解説")
        #expect(japanese[.paneExplanationAnalyzing] == "ペインを解析中…")
        #expect(english.commandTitle(.composeOneLiner) == "Compose One-Liner")
        #expect(japanese[.composeOneLiner] == "ワンライナー作成")
        #expect(english.commandTitle(.composeInput) == "Compose Input")
        #expect(japanese[.composeInput] == "テキストボックスから入力")
        #expect(
            english.commandTitle(.toggleFloatingPane)
                == "Toggle Floating Terminal"
        )
        #expect(japanese[.toggleFloatingPane] == "フローティングターミナルを切り替え")
        #expect(english[.floatingPane] == "Floating Terminal")
        #expect(japanese[.floatingPane] == "フローティングターミナル")
        #expect(english[.floatingPaneEdge] == "Slide in from")
        #expect(japanese[.floatingPaneEdge] == "スライドイン方向")
        #expect(english[.floatingPaneGlobalHotKey] == "Global hot key")
        #expect(japanese[.floatingPaneGlobalHotKey] == "グローバルホットキー")
        #expect(
            english[.floatingPaneGlobalHotKeyDescription]
                == "Reach the floating terminal from any app, not only while Mytty is frontmost."
        )
        #expect(
            japanese[.floatingPaneGlobalHotKeyDescription]
                == "Mytty が前面にないときも、どのアプリからでもフローティングターミナルを呼び出せるようにします。"
        )
        #expect(
            english[.floatingPaneGlobalHotKeyFailed]
                == "Couldn't register the global hot key. Another app may already use this combination."
        )
        #expect(
            japanese[.floatingPaneGlobalHotKeyFailed]
                == "グローバルホットキーを登録できませんでした。この組み合わせは他のアプリが使用している可能性があります。"
        )
        #expect(english[.inputComposerSend] == "Send")
        #expect(japanese[.inputComposerSend] == "送信")
        #expect(
            english[.inputComposerNoTerminalPane]
                == "Focus a terminal pane to send input."
        )
        #expect(
            japanese[.inputComposerNoTerminalPane]
                == "送信先のターミナルペインをフォーカスしてください。"
        )
        #expect(japanese[.edit] == "編集")
        #expect(japanese[.generate] == "生成")
        #expect(english[.development] == "Development")
        #expect(japanese[.development] == "開発")
        #expect(
            english[.importReleaseSettings] == "Import Settings from Mytty"
        )
        #expect(japanese[.importReleaseSettings] == "Mytty の設定をインポート")
        #expect(english[.releaseSettingsImported] == "Settings imported")
        #expect(japanese[.releaseSettingsImported] == "設定をインポートしました")
        #expect(
            english[.releaseSettingsNotFound]
                == "No Mytty release settings were found"
        )
        #expect(
            japanese[.releaseSettingsNotFound]
                == "Mytty リリース版の設定が見つかりませんでした"
        )
        #expect(
            english[.importReleaseSettingsDescription]
                == "Copy the installed Mytty release's settings into this development build."
        )
        #expect(
            japanese[.importReleaseSettingsDescription]
                == "インストール済みの Mytty (リリース版) の設定をこの開発ビルドにコピーします。"
        )
        #expect(
            english[.unableToImportReleaseSettings]
                == "Unable to import release settings"
        )
        #expect(
            japanese[.unableToImportReleaseSettings]
                == "リリース版の設定をインポートできませんでした"
        )
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
        #expect(english[.agentContextWarning] == "Warn on low context")
        #expect(
            english[.agentContextWarningDescription]
                == "Turn the status bar context meter red once the agent's "
                + "remaining context falls below the threshold."
        )
        #expect(english[.agentContextWarningThreshold] == "Warn below")
        #expect(english[.agentContextWarningStatus] == "Running low")
        #expect(english[.agentMeterDisplay] == "Meter shows")
        #expect(
            english[.agentMeterDisplayDescription]
                == "Choose whether the status bar meters graph what is left "
                + "of the context and usage limits, or how much of them has "
                + "been used."
        )
        #expect(english[.agentMeterDisplayRemaining] == "Remaining")
        #expect(english[.agentMeterDisplayUsed] == "Used")
        #expect(english.usedPercent(27) == "27% used")
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
            japanese[.agentContextWarning] == "コンテキスト残量が少ないときに警告"
        )
        #expect(
            japanese[.agentContextWarningDescription]
                == "エージェントのコンテキスト残量がこの割合を下回ったら、"
                + "ステータスバーの表示を赤くします。"
        )
        #expect(japanese[.agentContextWarningThreshold] == "警告する残量")
        #expect(japanese[.agentContextWarningStatus] == "残量わずか")
        #expect(japanese[.agentMeterDisplay] == "メーターの表示")
        #expect(
            japanese[.agentMeterDisplayDescription]
                == "ステータスバーのコンテキストと使用量のメーターに、残量と"
                + "使用量のどちらをグラフで表示するか選択します。"
        )
        #expect(japanese[.agentMeterDisplayRemaining] == "残量")
        #expect(japanese[.agentMeterDisplayUsed] == "使用量")
        #expect(japanese.usedPercent(27) == "27%使用")
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
        #expect(english[.releaseNotes] == "Release Notes")
        #expect(
            english[.viewReleaseNotes] == "View the release notes on GitHub"
        )
        #expect(english[.ago] == "ago")
        #expect(english[.moveToShell] == "Move to the shell")
        #expect(english[.scheduledInput] == "Scheduled Input")
        #expect(english[.newScheduledInput] == "New Scheduled Input")
        #expect(english[.scheduled] == "Scheduled")
        #expect(english[.dateAndTime] == "Date and time")
        #expect(english[.appendNewline] == "Append newline")
        #expect(english.commandTitle(.togglePaneZoom) == "Toggle Pane Zoom")
        #expect(english.commandTitle(.findInPane) == "Find in Pane")
        #expect(english.commandTitle(.reloadBrowser) == "Reload Page")
        #expect(english.commandTitle(.showPaneList) == "Show All Panes")
        #expect(english[.focusPane] == "Focus Pane")
        #expect(english[.noPanes] == "No panes are open.")
        #expect(english[.paneZoomed] == "Focused pane is zoomed")
        #expect(english[.paneProcesses] == "Running Processes")
        #expect(english.paneCount(3) == "3 panes")
        #expect(
            english[.hookHelperUnavailable]
                == "Hook helper is unavailable"
        )
        #expect(
            english[.teachPaneTeamPointers]
                == "Teach agents about Mytty orchestration"
        )
        #expect(
            english[.teachPaneTeamPointersDescription]
                == "For Claude Code and Codex, add a short reference to the bundled usage guide (mytty-ctl.md) that agents consult whenever a request mentions Mytty at all, not only when asked to run sub-agents across panes."
        )
        #expect(english[.orchestration] == "Orchestration")
        #expect(
            english[.orchestrationOverviewDescription].contains("mytty-ctl")
        )
        #expect(
            english[.orchestrationPointerTargetsHeading] == "Target files"
        )
        #expect(
            english[.orchestrationPointerGuideMarkdownFormat]
                == "Both files below just point at the guide Mytty writes and keeps up to date at %@."
        )
        #expect(
            english[.orchestrationPointerPreviewButton]
                == "Show what will be written"
        )
        #expect(
            english[.orchestrationExamplesHeading] == "How to ask for it"
        )
        #expect(
            english[.orchestrationExampleGuidanceOnLabel] == "Guidance on"
        )
        #expect(
            english[.orchestrationExampleGuidanceOffLabel] == "Guidance off"
        )
        #expect(
            english[.orchestrationExampleCurrentBadge]
                == "Matches your current setting"
        )
        #expect(
            english[.orchestrationExamplePromptGuided]
                == "Split the pane and have Claude Code review this diff in parallel."
        )
        #expect(
            english[.orchestrationExamplePromptUnguided]
                == "Run \"mytty-ctl guide\" first, then split the pane and have Claude Code review this diff in parallel."
        )
        #expect(english.commandTitle(.nextTab) == "Next Tab")
        #expect(english.commandTitle(.previousTab) == "Previous Tab")
        #expect(english.commandTitle(.nextWindow) == "Next Window")
        #expect(english.commandTitle(.previousWindow) == "Previous Window")
        #expect(english.commandTitle(.selectTab3) == "Go to Tab 3")
        #expect(english.commandTitle(.selectTab9) == "Go to Tab 9")
        #expect(
            english.toolRequiresApproval("Bash") == "Bash requires approval"
        )
        #expect(
            english.toolRequestsInput("AskUserQuestion")
                == "AskUserQuestion requests input"
        )
        #expect(
            japanese.toolRequiresApproval("Bash") == "Bash の承認が必要です"
        )
        #expect(
            japanese.toolRequestsInput("AskUserQuestion")
                == "AskUserQuestion が入力を求めています"
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
        #expect(japanese[.browserLoadFailed] == "ページを読み込めませんでした")
        #expect(japanese[.statusBar] == "ステータスバー")
        #expect(japanese[.inactivePaneDimming] == "非アクティブペインの暗さ")
        #expect(japanese[.activePaneBorder] == "アクティブペインの枠線")
        #expect(japanese[.activePaneBorderColor] == "枠線の色")
        #expect(japanese[.activePaneBorderWidth] == "枠線の太さ")
        #expect(japanese[.recording] == "入力キー表示")
        #expect(japanese[.confirmation] == "終了確認")
        #expect(japanese[.attention] == "通知")
        #expect(japanese[.toggleAttention] == "通知を表示")
        #expect(japanese.attentionCount(3) == "通知 3 件")
        #expect(japanese[.noItemsNeedAttention] == "通知はありません")
        #expect(japanese[.resolved] == "確認済")
        #expect(japanese[.closeAttention] == "通知パネルを閉じる")
        #expect(japanese[.input] == "入力")
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
        #expect(japanese[.moveToTab] == "別のタブへ移動")
        #expect(japanese[.terminalRecording] == "録画")
        #expect(japanese.commandTitle(.toggleRecording) == "録画を開始／停止")
        #expect(
            japanese.commandTitle(.togglePressedKeyToast)
                == "押したキーを表示／非表示"
        )
        #expect(
            japanese[.showPressedKeysInPane]
                == "押したキーをカーソルの下に表示"
        )
        #expect(
            japanese[.forceASCIIInputOnFocus]
                == "フォーカス復帰時、英数入力に切り替える"
        )
        #expect(
            japanese[.forceASCIIInputScopeShellIdleOnly] == "シェル待機中のみ"
        )
        #expect(japanese[.forceASCIIInputScopeAlways] == "常に")
        #expect(japanese[.stopRecording] == "録画を停止")
        #expect(japanese[.aboutMyTTY] == "Mytty について")
        #expect(japanese[.checkForUpdates] == "アップデートを確認")
        #expect(
            japanese[.checkForUpdatesPrereleaseHint]
                == "option を押しながらクリックすると pre-release も確認"
        )
        #expect(japanese[.update] == "アップデート")
        #expect(japanese[.releaseNotes] == "リリースノート")
        #expect(japanese[.viewReleaseNotes] == "GitHub でリリースノートを開く")
        #expect(japanese[.ago] == "前")
        #expect(japanese[.moveToShell] == "シェルへ移動")
        #expect(japanese[.scheduledInput] == "日時指定入力")
        #expect(japanese[.newScheduledInput] == "新規")
        #expect(japanese[.scheduled] == "設定済")
        #expect(japanese[.dateAndTime] == "日時")
        #expect(japanese[.appendNewline] == "改行を追加")
        #expect(japanese.commandTitle(.togglePaneZoom) == "ペインズームを切り替え")
        #expect(japanese.commandTitle(.findInPane) == "ペイン内を検索")
        #expect(japanese.commandTitle(.reloadBrowser) == "ページを再読み込み")
        #expect(japanese.commandTitle(.showPaneList) == "すべてのペインを表示")
        #expect(japanese[.focusPane] == "ペインへ移動")
        #expect(japanese[.noPanes] == "開いているペインはありません。")
        #expect(japanese[.paneZoomed] == "現在のペインを全体表示中")
        #expect(japanese[.paneProcesses] == "実行中のプロセス")
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
        #expect(
            japanese[.teachPaneTeamPointers]
                == "Agent に Mytty オーケストレーションの使い方を教える"
        )
        #expect(
            japanese[.teachPaneTeamPointersDescription]
                == "Claude Code と Codex に、同梱の使い方ガイド (mytty-ctl.md) への短い参照を追加します。複数ペインでサブエージェントを動かす依頼に限らず、依頼に Mytty が出てきた時点で agent が参照します。"
        )
        #expect(japanese[.orchestration] == "オーケストレーション")
        #expect(
            japanese[.orchestrationOverviewDescription].contains("mytty-ctl")
        )
        #expect(japanese[.orchestrationPointerTargetsHeading] == "対象ファイル")
        #expect(
            japanese[.orchestrationPointerGuideMarkdownFormat]
                == "以下のどちらのファイルも、Mytty が書き出して最新の状態に保つガイド (%@) を参照するだけです。"
        )
        #expect(
            japanese[.orchestrationPointerPreviewButton]
                == "書き込む内容を表示"
        )
        #expect(japanese[.orchestrationExamplesHeading] == "呼び出し方")
        #expect(japanese[.orchestrationExampleGuidanceOnLabel] == "案内あり")
        #expect(japanese[.orchestrationExampleGuidanceOffLabel] == "案内なし")
        #expect(
            japanese[.orchestrationExampleCurrentBadge] == "現在の設定"
        )
        #expect(
            japanese[.orchestrationExamplePromptGuided]
                == "ペインを分割して、この diff を Claude Code に並行でレビューさせて。"
        )
        #expect(
            japanese[.orchestrationExamplePromptUnguided]
                == "まず「mytty-ctl guide」を実行してから、ペインを分割してこの diff を Claude Code に並行でレビューさせて。"
        )
        #expect(japanese.commandTitle(.nextTab) == "次のタブ")
        #expect(japanese.commandTitle(.previousTab) == "前のタブ")
        #expect(japanese.commandTitle(.nextWindow) == "次のウィンドウ")
        #expect(japanese.commandTitle(.previousWindow) == "前のウィンドウ")
        #expect(japanese.commandTitle(.selectTab3) == "タブ 3 に移動")
        #expect(japanese.commandTitle(.selectTab9) == "タブ 9 に移動")
    }

    @Test("localizes the Finder service failure message")
    func finderServiceText() {
        let english = MyTTYLocalizer(language: .english)
        let japanese = MyTTYLocalizer(language: .japanese)

        #expect(
            english[.finderOpenNothingToOpen]
                == "No folder was available to open."
        )
        #expect(
            japanese[.finderOpenNothingToOpen]
                == "開けるフォルダがありませんでした"
        )
    }

    @Test("localizes the unsafe-paste confirmation dialog")
    func unsafePasteConfirmationText() {
        let english = MyTTYLocalizer(language: .english)
        let japanese = MyTTYLocalizer(language: .japanese)

        #expect(
            english[.unsafePasteTitle] == "Potentially Unsafe Paste"
        )
        #expect(
            english[.unsafePasteMessage]
                == "This text contains multiple lines or control characters that could run a command automatically once pasted."
        )
        #expect(
            japanese[.unsafePasteTitle] == "安全でない可能性があるペースト"
        )
        #expect(
            japanese[.unsafePasteMessage]
                == "このテキストには複数行または制御文字が含まれており、ペーストすると自動的にコマンドが実行される可能性があります。"
        )
    }

    @Test("localizes the QR-only remote pairing text")
    func remotePairingQRText() {
        let english = MyTTYLocalizer(language: .english)
        let japanese = MyTTYLocalizer(language: .japanese)

        #expect(english[.generatePairingCode] == "Generate Pairing QR Code")
        #expect(english[.pairingCode] == "Pair a Device")
        #expect(
            english[.pairingCodeInstructions]
                == "Scan this QR code with the Mytty iOS app within 2 minutes."
        )
        #expect(
            english[.pairingCodeExpired]
                == "This QR code has expired. Generate a new one."
        )
        #expect(japanese[.generatePairingCode] == "ペアリング用 QR コードを生成")
        #expect(japanese[.pairingCode] == "デバイスをペアリング")
        #expect(
            japanese[.pairingCodeInstructions]
                == "この QR コードを2分以内に Mytty iOS アプリでスキャンしてください。"
        )
        #expect(
            japanese[.pairingCodeExpired]
                == "この QR コードは失効しました。新しいものを生成してください。"
        )
    }

    @Test("localizes the push notification filter section titles")
    func pushNotificationFilterText() {
        let english = MyTTYLocalizer(language: .english)
        let japanese = MyTTYLocalizer(language: .japanese)

        #expect(
            english[.pushNotifiedAttentionKinds] == "Attention Types to Notify"
        )
        #expect(english[.pushNotifiedAgents] == "Agents to Notify")
        #expect(japanese[.pushNotifiedAttentionKinds] == "通知する Attention")
        #expect(japanese[.pushNotifiedAgents] == "通知するエージェント")
    }

    @Test("localizes the line bookmark context menu item and status bar list")
    func lineBookmarkText() {
        let english = MyTTYLocalizer(language: .english)
        let japanese = MyTTYLocalizer(language: .japanese)

        #expect(english[.addBookmark] == "Bookmark This Line")
        #expect(english[.bookmarks] == "Bookmarks")
        #expect(english[.emptyLineBookmark] == "(empty line)")
        #expect(english[.delete] == "Delete")
        #expect(japanese[.addBookmark] == "この行をブックマーク")
        #expect(japanese[.bookmarks] == "ブックマーク")
        #expect(japanese[.emptyLineBookmark] == "(空行)")
        #expect(japanese[.delete] == "削除")
    }
}
