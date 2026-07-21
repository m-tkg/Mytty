# mytty-ctl リファレンス

`mytty-ctl` は、コーディングエージェント(Claude Code、Codex、Cursor
など)が Mytty 自身を操作するためのローカル CLI。`agent` サブコマンドは
新しいペインに worker provider を起動し、タスクを1回のシェル入力として
渡し、その起動を1つの job として追跡する。orchestrator はその job を
待ち、結果を読み、追加指示を送れる。従来のペイン単位のコマンド
(`split`、`send`、`wait`、`read` など)もそのまま動き、ペインを手動で
操作するときの手段として残る。どちらを使うべきかは
[orchestration の how-to](../how-to/orchestrate-agents-with-mytty-ctl_ja.md)
を参照。`MyTTYApp` の `ControlServer` と、同一ユーザーに制限された Unix
ドメインソケット経由、1接続1 JSON リクエストで通信する。iOS リモート
(`RemoteAccessServer`、TCP + ペアリング + 暗号化)とは別系統の
トランスポート。出典は `Sources/MyTTYCore/ControlProtocol.swift`、
`Sources/MyTTYCore/ControlCommandLineParser.swift`、
`Sources/MyTTYCore/AgentJob.swift`、
`Sources/MyTTYCore/AgentLaunchPlan.swift`、
`Sources/MyTTYApp/ControlServer.swift`、
`Sources/MyTTYApp/ControlCoordinator.swift`、
`Sources/MyTTYApp/AgentJobCoordinator.swift`。

## 環境変数

Mytty が開くすべてのペインには次の3変数が自動設定される
(`AgentEventServer.environment(for:)`)。同じ箇所で `mytty-ctl` の
置き場所を `PATH` にも足しているので、ペイン内では `mytty-ctl`
と名前で呼ぶだけでよく、事前設定は不要。

| 変数 | 意味 |
| --- | --- |
| `MYTTY_CONTROL_SOCKET` | `mytty-ctl` が接続する Unix ソケットの絶対パス |
| `MYTTY_CTL_BIN` | `mytty-ctl` バイナリの絶対パス(名前で呼べるか怪しい場面向け) |
| `MYTTY_SURFACE_ID` | このペイン自身の pane ID。コマンド中で "自分自身" として使える |

```bash
mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd /path/to/worktree
```

dev ビルド(`Mytty Dev`)と release ビルドはそれぞれ別の
`~/.config/mytty(-dev)` 配下にソケットを持つが、`mytty-ctl` 自身はどちら
と通信しているかを意識しない。それはどのペインの環境変数を継承したかで
決まる。

## Mytty の外から使う

上の PATH 追加はあくまで Mytty が開いたペインの中だけの話。別の
ターミナルアプリやスクリプトなど、Mytty の外から `mytty-ctl` を
呼びたい場合は、設定 > Orchestration の「PATH にインストール」ボタンで
`~/.local/bin` にシンボリックリンクを作れる。管理者権限のプロンプトは
出ない。すでに同じ名前で別のもの(Mytty 以外を指すリンクや実ファイル)
があるときはボタンは失敗として扱い、黙って上書きはしない。

`~/.local/bin` がまだシェルの `PATH` に無い場合、インストール後に
次の行を追加するよう案内が表示される。

```bash
export PATH="$HOME/.local/bin:$PATH"
```

`.zshrc` など普段使っているシェルの設定ファイルに追記して、新しい
シェルを開くか設定を読み直せば `mytty-ctl` が名前で呼べるようになる。

開発ビルド(Mytty Dev)はリリース版のリンクを奪わないよう、
`~/.local/bin/mytty-ctl-dev` という別名でインストールする。

## 終了ステータスと出力

すべてのコマンドは成功時に JSON を1行だけ標準出力に印字し、終了コード
`0` で終わる。失敗時は標準エラーにメッセージを出し、終了コード `1` で
終わる。

```bash
mytty-ctl list | jq .
```

## コマンド一覧

「worker を1つ以上動かして結果を集める」形の作業には `agent`
コマンドを使う。worker の起動、その起動が実際に始めた実行の待機、
結果の読み取り、追加指示の送信をひとまとめに扱え、ペイン単位の
コマンドを組み合わせたときに呼び出し側が自分で避けなければならない
競合を心配しなくてよい(詳細は下の「job のバインディング」を参照)。
ペインを手動で
操作する用途にはペイン単位のコマンドを引き続き使う。

| コマンド | 引数 | 成功時のレスポンス |
| --- | --- | --- |
| `agent spawn` | `--provider <codex\|claude\|cursor> (--task <text>\|--task-file <path>) [--anchor <pane-id>] [--direction <left\|right\|up\|down>] [--cwd <path>] [--access <review\|workspace-write>] [--label <text>]` | `{"type":"agentJob","job":{...}}` |
| `agent wait` | `<job-id> --until <running\|attention\|completed> [--timeout-seconds <n>]` | `{"type":"agentWaitResult","job":{...},"timedOut":false}` |
| `agent result` | `<job-id>` | `{"type":"agentResult","job":{...},"content":{...}}` |
| `agent send` | `<job-id> <text> [--enter]` | `{"type":"ok"}` |
| `agent focus` | `<job-id>` | `{"type":"ok"}` |
| `agent close` | `<job-id>` | `{"type":"ok"}` |
| `guide` | なし | ペインチームの手順書をプレーンテキストで標準出力、ソケット不要 |
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
`pane` レスポンス、`$MYTTY_SURFACE_ID` のいずれかから取得する。job ID
は `AgentJobID` の `{"rawValue":"..."}` 形式の UUID で、
`agentJob`/`agentWaitResult`/`agentResult` レスポンスの
`job.jobID.rawValue` から取得する。

### agent spawn

`--anchor`(デフォルトは `$MYTTY_SURFACE_ID`)を分割して新しいペインを
作り、指定した provider を起動する。`--task`(または
`--task-file` の内容。ファイルはリクエストを送る前に `mytty-ctl`
自身が読む)は起動コマンドと合わせて1回のシェル入力として渡すので、
worker の TUI 起動と競合しうる別の `send` は発生しない。`--access` の
デフォルトは `workspace-write`。`review` を指定すると provider を
read-only/plan モードで起動する。すべてのタスクには worker contract
(作業ディレクトリの外に出ない、詰まったら止めずに続ける、最後に簡潔な
要約で締める、という指示)が自動で追記される。

```bash
job=$(mytty-ctl agent spawn \
  --provider codex --access review \
  --task "ログイン処理が高負荷時にタイムアウトする原因を調査して。" \
  --label investigate-a | jq -r '.job.jobID.rawValue')
```

```json
{
  "type": "agentJob",
  "job": {
    "jobID": { "rawValue": "..." },
    "paneID": { "rawValue": "..." },
    "provider": "codex",
    "label": "investigate-a",
    "state": "launching",
    "runID": null,
    "sessionID": null,
    "message": null
  }
}
```

`state` は最初 `launching` で、worker 自身の hook イベントが実行の
開始を確認した時点で `running` に変わる。`--task`/`--task-file` は
どちらか一方が必須。エンコード後のリクエストが 64 KiB のソケット
エンベロープを超えるタスクは、接続を開く前に CLI 側で拒否される。
`jobID` が実際に何を指しているかは
下の「job のバインディング」を参照。

### agent wait

その job がバインドした実行(job より前から存在していた実行ではない)
が指定条件に達するか、タイムアウトするまでブロックする。

```bash
mytty-ctl agent wait "$job" --until completed
```

```json
{
  "type": "agentWaitResult",
  "job": { "...": "agent spawn の job と同じ形" },
  "timedOut": false
}
```

- `running` は、job が実行にバインドし、その実行が running かそれより
  先に進んだ時点で解決する。
- `attention` は `waiting-input`/`waiting-approval` のときだけ解決する。
- `completed` は `succeeded`、`failed`、`disconnected`、
  `launch-failed`、`lost` のいずれかで解決する。

`--timeout-seconds` のデフォルトは `120`。provider が一度も起動しない
場合(実行ファイルが無い、hook 連携が壊れているなど)は spawn から
30秒以内に `launch-failed` になる。`agent wait` はこのケースでフル
タイムアウトまで待たない。

### agent result

job の最新状態と、そのペインの現在の画面内容を返す。`agent wait
--until completed` の後にこれを呼んで worker の成果を回収する。

```bash
mytty-ctl agent result "$job"
```

```json
{
  "type": "agentResult",
  "job": { "...": "agent spawn の job と同じ形" },
  "content": {
    "paneID": "...",
    "text": "...",
    "cursorRow": 10,
    "cursorColumn": 2
  }
}
```

これは provider のトランスクリプトではなくペインの現在の画面を読む
ため、起動時のプロンプトには最終的な要約を画面上で読める程度に簡潔に
まとめるよう指示している。

### agent send / agent focus / agent close

job ID をそのペインに解決し、ペイン単位の `send`/`focus`/`close-pane`
の挙動をそのまま再利用する。途中で他のペインが開いたり閉じたりして
いても、追加指示は常に意図した worker に届く。

```bash
mytty-ctl agent send "$job" "回帰テストも追加して。" --enter
mytty-ctl agent focus "$job"
mytty-ctl agent close "$job"
```

```json
{ "type": "ok" }
```

`agent close` は job のペインを閉じ、非終端状態の job を `lost` に
遷移させる。ユーザーがペインを閉じた、シェルが終了したなど自然に
ペインが消えた場合も同じ扱いになる。どの `agent` コマンドでも
`pane-not-found` ではなく `lost` として報告される。

### guide

ペインチームの手順書(環境変数、split/send/wait/read の流れ、provider
ごとの起動コマンド)をプレーンテキストで標準出力に出し、終了コード 0
で終わる。`MYTTY_CONTROL_SOCKET` も起動中の Mytty も不要。このファイル
はコマンド引数と JSON の形を説明する場所なので、手順の一次情報は
`mytty-ctl guide` の出力そのものを見ること。`mytty-ctl --help`(`-h`
や引数なしでも同じ)を実行すると、代わりに上のコマンド一覧が出る。

```bash
mytty-ctl guide
```

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
| `pane-not-found` | 指定した `pane-id` が生存中のペインに解決できない(`send`、`send-key`、`read`、`wait`、`close-pane`、`focus` でも返り得る)。`agent spawn` も `--anchor` が生存中のペインに解決できない場合にこれを返す |
| `provider-integration-not-installed` | `agent spawn`: 指定した provider の hook 連携が Settings で有効化されていない |
| `provider-integration-needs-repair` | `agent spawn`: provider の hook 連携は導入済みだが古くなっている、または壊れている |
| `invalid-cwd` | `agent spawn`: `--cwd` が実在するディレクトリを指していない |
| `invalid-label` | `agent spawn`: `--label` に制御文字が含まれる、または 100 Unicode スカラー値を超えている |
| `invalid-task` | `agent spawn`: 解決後のタスクテキストが空 |
| `spawn-failed` | `agent spawn`: ペインを作成できなかった |
| `job-not-found` | `agent wait`/`agent result`/`agent send`/`agent focus`/`agent close`: 指定した job ID が未知(そもそも存在しない、または直前の Mytty 再起動より前に発行されたもの。job ID は永続化されない) |
| `job-lost` | `agent send`/`agent focus`: job のペインが消えている(下記 `lost` を参照)。`agent result` と `agent close` はこのコードを使わない -- job の `lost` 状態と空の結果を返し、すでに消えているペインを閉じる操作も終了コード `0` になる |

## wait の意味論

`wait` は条件を満たすかタイムアウトするまで、一定間隔(約300ミリ秒)で
ポーリングする。

- `--until idle` は、対象ペインの直近のエージェント実行が `idle` /
  `succeeded` / `failed` / `disconnected` のいずれかになった時点で解決
  する。一度もエージェントイベントを受け取っていないペインはタイムアウト
  するまでブロックし続ける。「まだ何も来ていない=idle 扱い」という
  デフォルトは無い。
- `--until attention` は、実行状態が `waiting-input` または
  `waiting-approval` になった時点で解決する。Antigravity の導入済み
  hook は承認・入力待ちイベントを一切出さないため
  ([Agent providers](agent-providers_ja.md) 参照)、この provider が
  動くペインでは `wait --until attention` は常にタイムアウトする。
  Antigravity には `--until idle` を使う。Cursor も入力待ちイベントは
  出さないが、承認待ちには到達しうる: mytty は Cursor の `preToolUse`
  hook と、対応する `postToolUse` / `postToolUseFailure` との間隔から
  詰まった tool call を推定するため、その推定が発火した時点(何も
  解決しなければ tool call 開始からおおよそ10秒後)で Cursor ペインの
  `wait --until attention` も解決する。
- 対象 provider の hook 連携が設定でまだ有効化されていない場合、
  エージェントイベントが一切 Mytty に届かないため、条件に関わらず
  `wait` はタイムアウトするまでブロックし続ける。provider を初めて
  スクリプトから使うときに想定外のタイムアウトが起きる、最もよくある
  原因がこれ。

`agent wait` も同じようにポーリングするが、対象はペインではなく
`agent spawn` が作った job。条件も `wait`(`idle`/`attention`)とは
異なる3種類(`running`/`attention`/`completed`)になる。詳細は上の
[agent wait](#agent-wait) を参照。

## job のバインディング

`agent spawn` が作る job は「そのペインが今やっていること」全般では
なく、特定の1つの worker 実行を指す。内部では `AgentJobTracker` が、
新しいペインが作られた瞬間に既に存在する実行 ID の集合(新規ペインな
ので通常は空)を記録しておき、その後にそのペイン/provider について
観測した実行のうち、ID がその集合に含まれていない最初の実行に job を
バインドする。一度バインドすると、job が別の実行に切り替わることは
ない。これにより、連続して spawn した2つの job が互いの実行を誤って
観測することはなく、`agent wait --until completed` が job より前から
存在していた実行で解決してしまうこともない。

job の状態は、バインドした実行の `AgentRunState` を直接マッピングした
もので、ステータスバーが使う `AttentionCenter` の「このペインで最も
関連度の高い実行」というロジックは経由しない -- 両者は別の問いに答えて
いる。30秒以内にどの実行もバインドできなければ job は `launch-failed`
になる(実行ファイルが無い、TUI が一度も起動しなかった、hook が一度も
発火しなかった、のいずれもこれでカバーされる)。job のペインが消えたら
非終端状態の job は `lost` になる。どちらの遷移も後戻りしない。

job のレジストリは実行中のアプリのメモリ上にしかなく、永続化されない。
Mytty を再起動すると、それより前に発行された job ID は
`job-not-found` になる -- job が指していたペインやプロセス自体は
影響を受けず、その job ID からはもう辿れなくなるだけ。

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
  分割するか shell 経由でパイプする。`agent spawn` も、エンコード後の
  リクエスト(タスク本文 + 自動追記される worker contract)に対して
  同じ上限を接続前にチェックするので、大きすぎるタスクはソケット書き込み
  が黙って失敗するのではなく、その場で CLI のエラーになる。
- `agent spawn` は既存ペインに worker を起動することは一切なく、必ず
  新しいペインを作る。これは job のバインディングを正しく保つための
  前提(上の「job のバインディング」を参照)であり、少数のペインを手動で
  管理する場合よりも、不要になった job を `agent close` で閉じることの
  重要性が増すということでもある。
- job ID は `AgentJobID` の `{"rawValue":"..."}` 形式の UUID で、どの
  `agent` レスポンスでも `job.jobID.rawValue` から取得する。pane ID と
  は互換性が無い。

## 参考

- [mytty-ctl でエージェントチームを編成する](../how-to/orchestrate-agents-with-mytty-ctl_ja.md):
  `agent` コマンドを使った複数worker の段階的な例を扱っている。
- [mytty-ctl アーキテクチャ](../explanation/mytty-ctl-architecture_ja.md):
  control ソケットが事前設定不要で動く理由と、`agent wait` を支える
  job/実行のバインディングの仕組みを説明している。
- [Agent providers](agent-providers_ja.md): どの provider が
  承認・入力イベントを出すかをまとめている。`wait --until attention` に関係する。
- [エージェントイベントプロトコル](agent-event-protocol_ja.md):
  `list` と `wait` に出てくる `AgentProvider` と `AgentRunState` の値を定義している。
- `.claude/skills/mytty-panes/SKILL.md`: これらのコマンドを使った
  タスクレシピ集。
