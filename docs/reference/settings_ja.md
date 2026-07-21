# 設定リファレンス

Mytty の設定画面(Command-,)には General、Shell、Agents、Key Bindings、
Remote(サイドバー上は "iOS Remote Access" と表示)、Update の6セクションが
サイドバーに並ぶ。サイドバー上部の検索欄は
セクション名と各セクションに紐づく検索語で絞り込む(例えば "gemini" や
"sleep" と入力すると Agents が表示される)。このページは各セクションの
項目、デフォルト値、保存先を列挙する。出典は `SettingsView.swift`、
`AgentIntegrationSettingsView.swift`、`RemoteAccessSettingsView.swift`、
`PreferencesStore.swift`。

キーバインド一覧の全項目は
[キーボードショートカット](keyboard-shortcuts_ja.md) を参照。

## General

![General 設定画面。Application、Tabs、Input、Window、Confirmation の各グループ](../images/settings-general.png)

| グループ | 項目 | 種類 | デフォルト |
| --- | --- | --- | --- |
| Application | Language | メニュー: System Default / English / Japanese | System Default |
| Application | On Launch | メニュー: Restore last session / New window | Restore last session |
| Application | Default Terminal | ボタン "Make Default"(すでに `open` のデフォルトハンドラなら非表示) | 未設定 |
| Tabs | Position | セグメント: Left / Right / Top / Bottom | Left |
| Input | Show pressed keys in pane | トグル | オフ |
| Window | Mode | メニュー: Remember last size / Fullscreen / Small | Remember last size |
| Window | Status bar | トグル | オン |
| Confirmation | Close window | メニュー: When process running / Always | When process running |
| Confirmation | Close pane | メニュー: When process running / Always | When process running |
| Confirmation | Close tab | メニュー: When process running / Always | When process running |
| Confirmation | Close last pane in window | トグル | オン |

## Shell

![Shell 設定画面。Font、Appearance、Cursor、Shell、Autocomplete の各グループ](../images/settings-shell.png)

| グループ | 項目 | 種類 | デフォルト |
| --- | --- | --- | --- |
| Font | Family | インストール済み font family のメニュー | System Default(空文字) |
| Font | Size | 数値入力 + stepper、範囲 6-72 | 13 |
| Appearance | Mode | セグメント: System / Light / Dark | System |
| Appearance | Theme | Ghostty theme picker | 未設定(下の Text/Background 色を使う) |
| Appearance | Text / Background color | Color picker(Theme が未設定のときのみ表示) | Text `#FFFFFF`、Background `#282C34` |
| Appearance | Background opacity | スライダー、範囲 0.2-1.0 | 1.0(不透明) |
| Appearance | Inactive pane dimming | スライダー、範囲 0-0.8 | 0.32 |
| Appearance | Active pane border | トグル。枠線は分割中のタブでのみ表示される | On |
| Appearance | Border color | Color picker(枠線が On のときのみ表示) | システムのアクセントカラー(空文字列) |
| Appearance | Border width | スライダー、範囲 1-6(枠線が On のときのみ表示) | 2 |
| Cursor | Shape | セグメント: Block / Bar / Underline | Block |
| Cursor | Blink | メニュー: Terminal Default / On / Off | Terminal Default(system) |
| Shell | Default login shell | テキストフィールド | 空(ログインシェルを使う) |
| Autocomplete | Inline suggestions | トグル | オン |
| Autocomplete | Accept suggestion | 固定ラベル、編集不可 | Tab キー |

## Agents

![Agents 設定画面。sleep 抑止モードと provider ごとの導入行](../images/settings-agents.png)

| 行 | 項目 | 種類 | デフォルト |
| --- | --- | --- | --- |
| Unread items only | 通知パネルの絞り込み | トグル | オフ |
| Prevent sleep while an agent runs | sleep 抑止モード | メニュー: Allow sleep / Prevent while processing / Prevent while launched | Allow sleep |
| Teach agents about pane teams | Claude Code / Codex 向けペインチームのポインタ | トグル | オン |
| Codex | hook 連携の導入 | トグル + status(Not Installed / Installed / Needs Repair) | Not Installed |
| Claude Code | hook 連携の導入 | トグル + status | Not Installed |
| OpenCode | hook 連携の導入 | トグル + status | Not Installed |
| Gemini (Antigravity) | hook 連携の導入 | トグル + status | Not Installed |
| Cursor | hook 連携の導入 | トグル + status | Not Installed |

各 provider 行の status は、トグルを押したかどうかではなく実際の設定
ファイルの中身から導出される。**Not Installed**、**Installed**、
**Needs Repair**(ファイルは存在するが mytty 側のエントリが Mytty の外で
編集または部分的に削除された状態)の3値。**Needs Repair** の行には
mytty 自身の handler だけを書き直す repair ボタンが表示される。各
toggle がどのファイルを書き換えるかは
[Agent providers](agent-providers_ja.md) を、有効化の手順は
[エージェント連携の導入と検証](../how-to/install-agent-integrations_ja.md)
を参照。

**Teach agents about pane teams** は、provider のグローバル設定に短い
ポインタを書き込む機能。Claude Code なら
`~/.claude/skills/mytty-panes/SKILL.md` という skill、Codex なら
`~/.codex/AGENTS.md` 内の管理ブロックとして、複数ペインでの作業やサブ
エージェントの起動を頼まれたら `mytty-ctl guide` を実行するよう指示する。
上の hook 連携がすでに導入済みの provider にだけ効き、provider の導入・
削除にもこのトグルの設定が自動で追従する。Cursor・OpenCode・
Antigravity にはグローバルなポインタの置き場がまだ確認できていないため
対象外。

## Key Bindings

Application、Tabs、Panes、Terminal Recording の4グループに分かれた
記録可能な行が並ぶ。オンデバイスモデルのコマンド(Explain Pane、
Summarize Last Command、Compose One-Liner)は macOS 26 以降でのみ表示
される。行の recorder フィールドをクリックしてキーを押すとその
binding が設定され、記録中に Delete を押すと割り当てを消せる。丸い矢印
アイコンのボタンはその1コマンドをデフォルトに戻す。競合する binding は
行内にインラインで表示され、すでに同じ組み合わせを使っている相手の
コマンド名を示す。コマンドとデフォルト値の全一覧は
[キーボードショートカット](keyboard-shortcuts_ja.md) を参照。

## Remote

| 項目 | 種類 | デフォルト |
| --- | --- | --- |
| Enable Remote Access | トグル | オフ |
| Pairing code | 6桁コード。要求時に生成され、有効期限のカウントダウンと listening port を表示 | 未生成 |
| Paired devices | デバイスごとに Rename / Remove を持つリスト。ペアリング日時と push 登録状況を表示 | 空 |
| Enable Push Notifications | トグル。Remote Access がオンのときのみ表示 | オン |

Pairing Code と Paired Devices のセクションは **Enable Remote Access**
がオンのときだけ表示される。ペアリングと暗号化チャネルの設計は
`docs/ios-remote.md` 系列の explanation ページを参照。

## Update

![Update 設定画面。現在のバージョンと Check for Updates ボタン](../images/settings-update.png)

| 項目 | 種類 | 備考 |
| --- | --- | --- |
| Check for Updates | ボタン | GitHub Releases を確認する。通常クリックは stable release のみを対象にする |
| Check for Updates(option クリック) | ボタン(修飾) | pre-release(`x.y.z-beta.1`、`x.y.z-rc.N` など)も対象にし、見つかった最新のものへ update する |

Mytty は起動時と **About Mytty** を開いたときにも自動確認を行うが、
これら自動確認は stable release のみを対象にする。アプリ本体を置き換える
前に、download の digest、bundle identifier と version、Developer ID の
team 署名、内包コードの署名、Gatekeeper の判定を検証する。自動・手動の
self-update はどちらも Mytty Dev ビルドでは無効になる。

## データ保存先

以下は release ビルドのパス。Mytty Dev(`swift run Mytty`)は並行する
`mytty-dev` 系のディレクトリと、別の `com.m-tkg.mytty.dev` control
socket を使い、設定、session、利用量 cache は導入済み release と共有
しない。例外は provider の hook 導入で、provider 自身の設定ファイルが
global なため共有される。event の送信先だけはビルドごとに pane-scoped
のまま分かれる。

| データ | 保存先 |
| --- | --- |
| アプリ設定(General/Agents/Remote/key binding) | `~/.config/mytty/config.toml` |
| ターミナル設定(Shell セクション) | `~/.config/mytty/terminal.conf` |
| Agent 連携設定 | `~/.config/mytty/agents.toml` |
| Session、event、日時指定入力 | `~/Library/Application Support/mytty/` |
| Log | `~/Library/Logs/mytty/` |

`config.toml` は各設定値を Mytty が管理する固定キーの下に保存する
(例: `tab-position`、`on-launch`、`agents.prevent-system-sleep`、
`pane.inactive-dimming`、`pane.active-border` とその
`-width` / `-color`、customize 可能なコマンドごとの
`keybinding.<command>`)。これらの管理対象キー以外の行は保存時にそのまま
保持される。管理対象キーのうち `keybinding.toggle-attention` の1つは
スキーマ上予約されているだけで、実際に読み書きするコードは存在しない。
View メニューに **Toggle Attention(通知パネルを切り替え)** 項目は
あるものの、現在のアプリではキーボードショートカットが割り当てられて
いない。
