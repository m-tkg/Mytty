# キーボードショートカット リファレンス

**Toggle Attention** を除き、以下はすべて `MyTTYCommand` であり
**設定 > Key Bindings** から確認・変更・削除できる
(`KeyBindingSettingsCatalog.swift`、デフォルト値は `KeyBinding.swift`)。
**Split Left** と **Split Up** の2コマンドはデフォルトの binding を持た
ないが、Key Bindings 画面には表示され、そこでキーを割り当てられる。
「macOS 26+」と書かれたコマンドは、オンデバイスの Foundation Models
framework 上で動くため、macOS 26 以降でのみメニューと Key Bindings に
表示される。

## Application

| コマンド | デフォルト shortcut |
| --- | --- |
| Settings | Command-, |
| Quit Mytty | Command-Q |
| New Window | Command-N |
| Next Window | Command-` |
| Previous Window | Command-Shift-` |
| Open HTML File | Command-O |
| Command Palette | Command-Shift-P |
| Compose One-Liner (macOS 26+) | Control-Command-K |

## Tabs

| コマンド | デフォルト shortcut |
| --- | --- |
| New Tab | Command-T |
| Rename Tab | Command-R |
| Close Tab | Command-W |
| Reopen Closed Item | Command-Shift-T |
| Toggle Tab Panels | Command-B |
| Next Tab | Control-Tab |
| Previous Tab | Control-Shift-Tab |
| Go to Tab 1-9 | Command-1 ... Command-9 |

タブの番号はタブが開閉したりドラッグで並び替わったりするたびに上から
1, 2, 3... と振り直され、サイドバーの各タブではドラッグハンドルの下に
現在の番号が表示される。Command-9 は「9 番目のタブ」へのジャンプで、
タブが 9 個未満のときは何も起きない(最後のタブへ飛ぶわけではない)。

## Panes

| コマンド | デフォルト shortcut |
| --- | --- |
| Show All Panes | Control-Command-P |
| Split Left | 未設定 |
| Split Right | Command-D |
| Split Up | 未設定 |
| Split Down | Command-Shift-D |
| Focus Left | Command-Option-Left |
| Focus Right | Command-Option-Right |
| Focus Up | Command-Option-Up |
| Focus Down | Command-Option-Down |
| Equalize Panes | Control-Command-= |
| Toggle Pane Zoom | Control-Command-Return |
| Swap Panes | Control-Command-S |
| Find in Pane | Control-F |
| Close Pane | Command-Shift-W |
| Explain Pane (macOS 26+) | Control-Command-I |
| Summarize Last Command (macOS 26+) | Control-Command-J |

## Terminal Recording

| コマンド | デフォルト shortcut |
| --- | --- |
| Start/Stop Recording | Command-Shift-G |

## カスタマイズできないメニューコマンド

**Toggle Attention**(View メニュー、通知パネルの表示/非表示)は
`MyTTYCommand` ではない。`KeyBindingSettingsCatalog` にエントリが無く、
`MyTTYCommand.defaultKeyBindings` にもデフォルトが無く、
`MainMenuBuilder.swift` のメニュー項目自体が空の `keyEquivalent` で
組み立てられている。現在の実装では設定画面からこのコマンドにキーを
割り当てることはできず、コードベースの他のキーモニターもこれを bind
していない。`config.toml` のスキーマには
`keybinding.toggle-attention` というキーが予約されているが、これを
読み書きするコードパスは存在しないため、このファイルを手で編集して
値を入れても効果は無い。つまり現行ビルドではこのショートカットに
デフォルトのキー割り当てが存在せず、アプリ内やドキュメントの一部に
ある「Command-Shift-A」という記述とは食い違っている。

## 表記について

文中の `Command-Option-Arrow` は、上表の4方向すべてが個別に割り当て
られていることを指す。custom binding の表示に使われるキー名は
`KeyBindingRecorder` の表示と同じで、矢印は `←↑→↓`、Return は `↩`、
修飾キーは Control(`⌃`)- Option(`⌥`)- Shift(`⇧`)- Command(`⌘`)の
固定順で並ぶ。
