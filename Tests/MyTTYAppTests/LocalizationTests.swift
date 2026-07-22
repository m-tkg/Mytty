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
        #expect(english[.browserLoadFailed] == "Failed to load page")
        #expect(english[.statusBar] == "Status Bar")
        #expect(english[.inactivePaneDimming] == "Inactive pane dimming")
        #expect(english[.activePaneBorder] == "Active pane border")
        #expect(english[.activePaneBorderColor] == "Border color")
        #expect(english[.activePaneBorderWidth] == "Border width")
        #expect(english[.updates] == "Updates")
        #expect(english[.defaultTerminal] == "Default Terminal")
        #expect(english[.makeDefaultTerminal] == "Make Mytty Default")
        #expect(english[.defaultTerminalActive] == "Mytty is the default terminal.")
        #expect(english[.commandLineTool] == "Command Line Tool")
        #expect(english[.installCommandLineTool] == "Install CLI")
        #expect(english[.commandLineToolInstalled] == "%@ is on your PATH.")
        #expect(
            english[.commandLineToolConflict]
                == "Something else already exists at ~/.local/bin/%@. Remove it, then try again."
        )
        #expect(
            english[.commandLineToolInstallFailed] == "Couldn't install %@."
        )
        #expect(
            english[.commandLineToolPathHint]
                == "~/.local/bin isn't on your PATH yet. Add this to your shell profile: %@"
        )
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
        #expect(english[.newTabPosition] == "New Tab Position")
        #expect(japanese[.newTabPosition] == "新規タブの位置")
        #expect(english[.newTabPositionEnd] == "At the End")
        #expect(japanese[.newTabPositionEnd] == "末尾")
        #expect(english[.newTabPositionAfterCurrent] == "After Current Tab")
        #expect(japanese[.newTabPositionAfterCurrent] == "現在のタブの次")
        #expect(english[.showTabUptime] == "Show Elapsed Time in Tabs")
        #expect(japanese[.showTabUptime] == "タブに経過時間を表示")
        #expect(english[.tabUptime] == "Elapsed Time")
        #expect(japanese[.tabUptime] == "経過時間")
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
        #expect(english.commandTitle(.reloadBrowser) == "Reload Page")
        #expect(english.commandTitle(.showPaneList) == "Show All Panes")
        #expect(english[.focusPane] == "Focus Pane")
        #expect(english[.noPanes] == "No panes are open.")
        #expect(english[.paneZoomed] == "Focused pane is zoomed")
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
                == "For Claude Code and Codex, add a short reference to the bundled usage guide (mytty-ctl.md) when asked to run sub-agents across panes."
        )
        #expect(english[.orchestration] == "Orchestration")
        #expect(
            english[.orchestrationOverviewDescription].contains("mytty-ctl")
        )
        #expect(
            english[.orchestrationCommandLineToolDescriptionFormat]
                == "A symlink to mytty-ctl, placed at ~/.local/bin/%@. Panes Mytty opens already have it on PATH, so this only matters for calling mytty-ctl from outside Mytty: another terminal app or a script."
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
            english[.orchestrationExampleGuidanceOnCLIInstalledLabel]
                == "Guidance on, CLI installed"
        )
        #expect(
            english[.orchestrationExampleGuidanceOnCLINotInstalledLabel]
                == "Guidance on, CLI not installed"
        )
        #expect(
            english[.orchestrationExampleGuidanceOffLabel] == "Guidance off"
        )
        #expect(
            english[.orchestrationExampleCLINote]
                == "Inside a Mytty pane, mytty-ctl is already on PATH either way, so these two read the same. Installing the CLI to PATH only matters outside Mytty."
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
        #expect(japanese[.input] == "入力待ち")
        #expect(japanese[.updates] == "アップデート")
        #expect(japanese[.defaultTerminal] == "デフォルトターミナル")
        #expect(japanese[.makeDefaultTerminal] == "Mytty をデフォルトにする")
        #expect(japanese[.defaultTerminalActive] == "Mytty はデフォルトターミナルです。")
        #expect(japanese[.commandLineTool] == "コマンドラインツール")
        #expect(japanese[.installCommandLineTool] == "CLI をインストール")
        #expect(japanese[.commandLineToolInstalled] == "%@ が PATH に追加されています。")
        #expect(
            japanese[.commandLineToolConflict]
                == "~/.local/bin/%@ に別のものが存在します。削除してからもう一度お試しください。"
        )
        #expect(
            japanese[.commandLineToolInstallFailed] == "%@ をインストールできませんでした。"
        )
        #expect(
            japanese[.commandLineToolPathHint]
                == "~/.local/bin がまだ PATH に含まれていません。シェルの設定ファイルに次の行を追加してください: %@"
        )
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
        #expect(japanese.commandTitle(.reloadBrowser) == "ページを再読み込み")
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
        #expect(
            japanese[.teachPaneTeamPointers]
                == "Agent に Mytty オーケストレーションの使い方を教える"
        )
        #expect(
            japanese[.teachPaneTeamPointersDescription]
                == "Claude Code と Codex に、複数ペインでサブエージェントを動かす際は同梱の使い方ガイド (mytty-ctl.md) への短い参照を追加します。"
        )
        #expect(japanese[.orchestration] == "オーケストレーション")
        #expect(
            japanese[.orchestrationOverviewDescription].contains("mytty-ctl")
        )
        #expect(
            japanese[.orchestrationCommandLineToolDescriptionFormat]
                == "mytty-ctl へのシンボリックリンクを ~/.local/bin/%@ に作成します。Mytty が開いたペインではすでに PATH が通っているため、これが必要なのは Mytty の外(別のターミナルアプリやスクリプト)から mytty-ctl を呼びたい場合だけです。"
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
        #expect(
            japanese[.orchestrationExampleGuidanceOnCLIInstalledLabel]
                == "案内あり・CLI インストール済み"
        )
        #expect(
            japanese[.orchestrationExampleGuidanceOnCLINotInstalledLabel]
                == "案内あり・CLI 未インストール"
        )
        #expect(japanese[.orchestrationExampleGuidanceOffLabel] == "案内なし")
        #expect(
            japanese[.orchestrationExampleCLINote]
                == "Mytty のペイン内ではどちらの場合も mytty-ctl の PATH が通っているため、実際には同じ書き方になります。差が出るのは Mytty の外から使う場合だけです。"
        )
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
}
