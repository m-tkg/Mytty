# mytty-ctl リファレンス

`mytty-ctl` は、コーディングエージェント(Claude Code、Codex、Cursor
など)が Mytty 自身を操作するためのローカル CLI。ペインの作成・分割、
テキストやキー入力の送信、画面の読み取り、エージェント実行の idle/
attention 待機ができる。`MyTTYApp` の `ControlServer` と、同一ユーザーに
制限された Unix ドメインソケット経由、1接続1 JSON リクエストで通信する。
iOS リモート(`RemoteAccessServer`、TCP + ペアリング + 暗号化)とは別系統
のトランスポート。出典は `Sources/MyTTYCore/ControlProtocol.swift`、
`Sources/MyTTYCore/ControlCommandLineParser.swift`、
`Sources/MyTTYApp/ControlServer.swift`、
`Sources/MyTTYApp/ControlCoordinator.swift`。

## 環境変数

Mytty が開くすべてのペインには次の3変数が自動設定される
(`AgentEventServer.environment(for:)`)。そのためペイン内から
`mytty-ctl` を呼ぶのに事前設定は不要。

| 変数 | 意味 |
| --- | --- |
| `MYTTY_CONTROL_SOCKET` | `mytty-ctl` が接続する Unix ソケットの絶対パス |
| `MYTTY_CTL_BIN` | `mytty-ctl` バイナリの絶対パス(`PATH` 登録不要) |
| `MYTTY_SURFACE_ID` | このペイン自身の pane ID。コマンド中で "自分自身" として使える |

```bash
"$MYTTY_CTL_BIN" split "$MYTTY_SURFACE_ID" right --cwd /path/to/worktree
```

`mytty-ctl` が `PATH` に通っていれば、名前だけで呼んでも同じように動く。
dev ビルド(`Mytty Dev`)と release ビルドはそれぞれ別の
`~/.config/mytty(-dev)` 配下にソケットを持つが、`mytty-ctl` 自身はどちら
と通信しているかを意識しない。それはどのペインの環境変数を継承したかで
決まる。

## 終了ステータスと出力

すべてのコマンドは成功時に JSON を1行だけ標準出力に印字し、終了コード
`0` で終わる。失敗時は標準エラーにメッセージを出し、終了コード `1` で
終わる。

```bash
mytty-ctl list | jq .
```

## コマンド一覧

| コマンド | 引数 | 成功時のレスポンス |
| --- | --- | --- |
| `list` | なし | `{"type":"list","panes":[...]}` |
| `new-tab` | `[--cwd <path>]` | `{"type":"pane","paneID":"..."}` |
| `split` | `<pane-id> <left\|right\|up\|down> [--cwd <path>]` | `{"type":"pane","paneID":"..."}` |
| `send` | `<pane-id> <text> [--enter]` | `{"type":"ok"}` |
| `send-key` | `<pane-id> <key> [--modifiers <mod,mod,...>]` | `{"type":"ok"}` |
| `read` | `<pane-id>` | `{"type":"content","content":{...}}` |
| `wait` | `<pane-id> --until <idle\|attention> [--timeout-seconds <n>]` | `{"type":"waitResult","state":"...","timedOut":false}` |
| `close-pane` | `<pane-id>` | `{"type":"ok"}` |
| `focus` | `<pane-id>` | `{"type":"ok"}` |

pane ID は `TerminalSurfaceID` の UUID 文字列。`list` のレスポンス、
`pane` レスポンス、`$MYTTY_SURFACE_ID` のいずれかから取得する。

### list

開いている全ウィンドウの全ペインを一覧する。

```bash
mytty-ctl list
```

![Mytty のペイン内で実行した `mytty-ctl list | jq .`。まだエージェント履歴の無いペイン](../images/mytty-ctl-list.png)

```json
{
  "type": "list",
  "panes": [
    {
      "paneID": "B9AA8B83-B42D-4C11-B838-36B84C73032A",
      "windowID": "...",
      "tabID": "...",
      "title": "zsh",
      "command": "zsh",
      "workingDirectory": "/Users/me/project",
      "isActive": true,
      "provider": "codex",
      "agentState": "running"
    }
  ]
}
```

`provider` は `AgentProvider.rawValue`(
[エージェントイベントプロトコル](agent-event-protocol_ja.md) 参照)、
`agentState` は `AgentRunState.rawValue`。そのペインにまだ1件も
エージェントイベントが記録されていなければ、`null` にはならず両方の
キー自体が JSON から消える(エージェント履歴の無いペインで実際に
`mytty-ctl list | jq .` を実行して確認済み。`provider` も `agentState`
も出力に現れない)。

### new-tab

アクティブウィンドウ(なければ最初に見つかったウィンドウ)に新規タブを
作成する。特定のウィンドウを狙って指定する方法はない。特定のウィンドウ
に作りたい場合はそのウィンドウの既存ペインを `split` する。

```bash
mytty-ctl new-tab --cwd /path/to/project
```

```json
{ "type": "pane", "paneID": "..." }
```

`--cwd` を省略するとアクティブウィンドウの現在の作業ディレクトリを
継承する。

### split

指定ペインを対象方向に分割する。分割対象のペインは自動でフォーカスして
から分割する。

```bash
mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd /tmp
```

```json
{ "type": "pane", "paneID": "..." }
```

### send

ペインにテキストを送信する。`--enter` を付けると続けて Enter も送る。

```bash
mytty-ctl send "$paneA" "claude" --enter
mytty-ctl send "$paneA" "issue #42 を調査して" --enter
```

```json
{ "type": "ok" }
```

### send-key

単発のキーイベントを送る。プレーンテキストでは反応しない対話的な
プロンプト(矢印キーで選ぶメニュー、キャンセル用の `Esc` など)に使う。

```bash
mytty-ctl send-key "$paneA" escape
mytty-ctl send-key "$paneA" up
mytty-ctl send-key "$paneA" c --modifiers control
```

`<key>` に指定できる値(`RemoteKeyMapping.swift`):

| 分類 | 値 |
| --- | --- |
| 名前付きキー | `escape`、`tab`、`return`、`delete`、`space`、`up`、`down`、`left`、`right`、`f1`-`f12` |
| 単一文字 | `a`-`z`、`0`-`9`、`` ` ``、`-`、`=`、`[`、`]`、`\`、`;`、`'`、`,`、`.`、`/` のいずれか1文字 |

`--modifiers` は `shift`、`control`、`option`、`command` からカンマ区切り
で指定する(例: `--modifiers shift,command`)。未対応の `<key>` を渡すと
ペインが実在していても `pane-not-found` エラーになる。
`ControlCoordinator` は「キーマッピングが無い」場合と「そのペインが無い」
場合を区別せず同じ扱いにしているため、このケースに限りエラーコードの
名前と実態が食い違う。この場合キーイベントは送信されない。

```json
{ "type": "ok" }
```

### read

ペインの現在の画面テキストとカーソル位置を取得する。

```bash
mytty-ctl read "$paneA"
```

```json
{
  "type": "content",
  "content": {
    "paneID": "...",
    "text": "$ ls\nREADME.md\n...",
    "cursorRow": 3,
    "cursorColumn": 0
  }
}
```

カーソル位置を報告できない場合、`cursorRow` と `cursorColumn` は
`null` になる。

### wait

対象ペインの直近のエージェント実行が条件を満たすか、タイムアウトする
までブロックする。

```bash
mytty-ctl wait "$paneA" --until idle
mytty-ctl wait "$paneA" --until attention --timeout-seconds 600
```

```json
{ "type": "waitResult", "state": "idle", "timedOut": false }
```

`--timeout-seconds` のデフォルトは `120`。`state` は wait が解決した
時点で観測された `AgentRunState`(そのペインに一度もイベントが来ていな
ければ `null`)。`timedOut` はタイムアウトまでに条件を満たせなかった
場合に `true` になる。詳細は下記「wait の意味論」を参照。

### close-pane

確認ダイアログを出さずに即座にペインを閉じる。呼び出し元は人間が Close
をクリックしたのではなく自動化されたエージェントである、という前提に
立っている。

```bash
mytty-ctl close-pane "$paneA"
```

```json
{ "type": "ok" }
```

ウィンドウ内で最後のタブの最後のペインを閉じる場合、そのウィンドウ自体
のクローズ確認ダイアログ(ユーザーが設定していれば)は依然として出る。
サブエージェント用に作ったペインでは通常この状況は起きない。

### focus

指定ペインを前面にフォーカスする。制御をユーザーに戻したいときに使う。

```bash
mytty-ctl focus "$paneA"
```

```json
{ "type": "ok" }
```

## 失敗時のレスポンス

失敗したリクエストにはサーバーから
`{"type":"failure","code":"..."}` が返る。CLI 側はこれを JSON として
印字せず、非ゼロの終了コードと標準エラーへのメッセージとして表現する。

| コード | 意味 |
| --- | --- |
| `invalid-request` | JSON としてデコードできなかった、または CLI 側の引数構文が不正 |
| `not-ready` | control server にまだ delegate が設定されていない(アプリ起動中) |
| `new-tab-failed` | `new-tab` がタブを作成できなかった |
| `split-failed` | `split` が指定ペインを分割できなかった |
| `pane-not-found` | 指定した `pane-id` が生存中のペインに解決できない(`send`、`send-key`、`read`、`wait`、`close-pane`、`focus` でも返り得る) |

## wait の意味論

`wait` は条件を満たすかタイムアウトするまで、一定間隔(約300ミリ秒)で
ポーリングする。

- `--until idle` は、対象ペインの直近のエージェント実行が `idle` /
  `succeeded` / `failed` / `disconnected` のいずれかになった時点で解決
  する。一度もエージェントイベントを受け取っていないペインはタイムアウト
  するまでブロックし続ける。「まだ何も来ていない=idle 扱い」という
  デフォルトは無い。
- `--until attention` は、実行状態が `waiting-input` または
  `waiting-approval` になった時点で解決する。Cursor と Antigravity の
  導入済み hook は承認・入力待ちイベントを一切出さないため
  ([Agent providers](agent-providers_ja.md) 参照)、これらの provider が
  動くペインでは `wait --until attention` は常にタイムアウトする。
  この2 provider には `--until idle` を使う。
- 対象 provider の hook 連携が設定でまだ有効化されていない場合、
  エージェントイベントが一切 Mytty に届かないため、条件に関わらず
  `wait` はタイムアウトするまでブロックし続ける。provider を初めて
  スクリプトから使うときに想定外のタイムアウトが起きる、最もよくある
  原因がこれ。

## 制約・注意点

- `new-tab` はどのウィンドウに作るかを明示的に指定できず、アクティブ
  ウィンドウ(なければ最初に見つかったウィンドウ)に作られる。特定の
  ウィンドウを狙いたい場合は、そのウィンドウの既存ペインを `split`
  すること。
- `close-pane` は確認ダイアログを出さずに即座に閉じる。唯一の例外(
  ウィンドウ内最後のタブの最後のペインを閉じる場合にウィンドウ自体の
  確認ダイアログが出るケース)は、サブエージェント用ペインの通常運用で
  はまず発生しない。
- pane ID は `TerminalSurfaceID` の UUID 文字列。`list` のレスポンス、
  `pane` レスポンス、`$MYTTY_SURFACE_ID` のいずれかから取得する。
- control ソケットが受け付けるリクエストの最大サイズは、エージェント
  イベントソケットと同じ 64 KiB のエンベロープ上限に合わせてある。
  非常に大きな `send` の引数は、1つの巨大なリテラルとして渡すのではなく
  分割するか shell 経由でパイプする。

## 参考

- [Agent providers](agent-providers_ja.md): どの provider が
  承認・入力イベントを出すかをまとめている。`wait --until attention` に関係する。
- [エージェントイベントプロトコル](agent-event-protocol_ja.md):
  `list` と `wait` に出てくる `AgentProvider` と `AgentRunState` の値を定義している。
- `.claude/skills/mytty-panes/SKILL.md`: これらのコマンドを使った
  タスクレシピ集。
