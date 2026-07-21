# mytty-ctl リファレンス

`mytty-ctl` は、コーディングエージェント(Claude Code、Codex、Cursor など)が Mytty 自身を操作するためのローカル CLI です。`agent` サブコマンドは新しいペインに worker provider を起動し、タスクを1回のシェル入力として渡して、その起動を1つの job として追跡します。orchestrator はその job を待ち、結果を読み、追加指示を送れます。従来のペイン単位のコマンド(`split`、`send`、`wait`、`read` など)もそのまま使えるので、ペインを手動で操作したいときはこちらを使ってください。どちらを使うべきかは [orchestration の how-to](../how-to/orchestrate-agents-with-mytty-ctl_ja.md)を参照してください。通信には `MyTTYApp` の `ControlServer` を使い、同一ユーザーに制限された Unix ドメインソケット経由で、1接続につき1つの JSON リクエストをやりとりします。iOS リモート(`RemoteAccessServer`、TCP + ペアリング + 暗号化)とは別系統のトランスポートです。出典は `Sources/MyTTYCore/ControlProtocol.swift`、`Sources/MyTTYCore/ControlCommandLineParser.swift`、`Sources/MyTTYCore/AgentJob.swift`、`Sources/MyTTYCore/AgentLaunchPlan.swift`、`Sources/MyTTYApp/ControlServer.swift`、`Sources/MyTTYApp/ControlCoordinator.swift`、`Sources/MyTTYApp/AgentJobCoordinator.swift`。

## 環境変数

Mytty が開くすべてのペインには、次の3変数が自動で設定されます(`AgentEventServer.environment(for:)`)。同じ箇所で `mytty-ctl` の置き場所を `PATH` にも足しているので、ペイン内では `mytty-ctl` と名前で呼ぶだけで使え、事前設定は不要です。

| 変数 | 意味 |
| --- | --- |
| `MYTTY_CONTROL_SOCKET` | `mytty-ctl` が接続する Unix ソケットの絶対パス |
| `MYTTY_CTL_BIN` | `mytty-ctl` バイナリの絶対パス(名前で呼べるか怪しい場面向け) |
| `MYTTY_SURFACE_ID` | このペイン自身の pane ID。コマンド中で "自分自身" として使える |

```bash
mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd /path/to/worktree
```

dev ビルド(`Mytty Dev`)と release ビルドは、それぞれ別の `~/.config/mytty(-dev)` 配下にソケットを持ちます。`mytty-ctl` 自身はどちらと通信しているかを意識しません。どちらと通信するかは、どのペインの環境変数を継承したかで決まります。

## Mytty の外から使う

上の PATH 追加は、あくまで Mytty が開いたペインの中だけの話です。別のターミナルアプリやスクリプトなど、Mytty の外から `mytty-ctl` を呼びたい場合は、設定 > Orchestration の「CLI をインストール」ボタンで `~/.local/bin` にシンボリックリンクを作れます。管理者権限のプロンプトは出ません。すでに同じ名前で別のもの(Mytty 以外を指すリンクや実ファイル)があるときは、ボタンは失敗として扱われ、黙って上書きされることはありません。

`~/.local/bin` がまだシェルの `PATH` に無い場合は、インストール後に次の行を追加するよう案内が表示されます。

```bash
export PATH="$HOME/.local/bin:$PATH"
```

`.zshrc` など普段使っているシェルの設定ファイルに追記し、新しいシェルを開くか設定を読み直せば、`mytty-ctl` を名前で呼べるようになります。

開発ビルド(Mytty Dev)は、リリース版のリンクを奪わないよう `~/.local/bin/mytty-ctl-dev` という別名でインストールします。

## 終了ステータスと出力

すべてのコマンドは、成功時に JSON を1行だけ標準出力に印字し、終了コード `0` で終わります。失敗時は標準エラーにメッセージを出し、終了コード `1` で終わります。

```bash
mytty-ctl list | jq .
```

## コマンド一覧

「worker を1つ以上動かして結果を集める」形の作業には `agent` コマンドを使ってください。worker の起動、その起動が実際に始めた実行の待機、結果の読み取り、追加指示の送信をひとまとめに扱えます。ペイン単位のコマンドを組み合わせたときに呼び出し側が自分で避けなければならない競合も、心配する必要がありません(詳細は下の「job のバインディング」を参照)。ペインを手動で操作する用途には、引き続きペイン単位のコマンドを使ってください。

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

pane ID は `TerminalSurfaceID` の UUID 文字列です。`list` のレスポンス、`pane` レスポンス、`$MYTTY_SURFACE_ID` のいずれかから取得できます。job ID は `AgentJobID` の `{"rawValue":"..."}` 形式の UUID で、`agentJob`/`agentWaitResult`/`agentResult` レスポンスの `job.jobID.rawValue` から取得します。

### agent spawn

`--anchor`(デフォルトは `$MYTTY_SURFACE_ID`)を分割して新しいペインを作り、指定した provider を起動します。`--task`(または `--task-file` の内容。ファイルはリクエストを送る前に `mytty-ctl` 自身が読みます)は、起動コマンドと合わせて1回のシェル入力として渡すので、worker の TUI 起動と競合しうる別の `send` は発生しません。`--access` のデフォルトは `workspace-write` です。`review` を指定すると provider を read-only/plan モードで起動します。すべてのタスクには worker contract(作業ディレクトリの外に出ない、詰まったら止めずに続ける、最後に簡潔な要約で締める、という指示)が自動で追記されます。

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

`state` は最初 `launching` で、worker 自身の hook イベントが実行の開始を確認した時点で `running` に変わります。`--task`/`--task-file` はどちらか一方が必須です。エンコード後のリクエストが 64 KiB のソケットエンベロープを超えるタスクは、接続を開く前に CLI 側で拒否されます。`jobID` が実際に何を指しているかは、下の「job のバインディング」を参照してください。

### agent wait

その job がバインドした実行(job より前から存在していた実行ではありません)が指定条件に達するか、タイムアウトするまでブロックします。

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

- `running` は、job が実行にバインドし、その実行が running かそれより先に進んだ時点で解決します。
- `attention` は `waiting-input`/`waiting-approval` のときだけ解決します。
- `completed` は `succeeded`、`failed`、`disconnected`、`launch-failed`、`lost` のいずれかで解決します。

`--timeout-seconds` のデフォルトは `120` です。provider が一度も起動しない場合(実行ファイルが無い、hook 連携が壊れているなど)は、spawn から30秒以内に `launch-failed` になります。`agent wait` はこのケースで、フルタイムアウトまで待ちません。

### agent result

job の最新状態と、そのペインの現在の画面内容を返します。`agent wait --until completed` の後にこれを呼び、worker の成果を回収します。

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

これは provider のトランスクリプトではなく、ペインの現在の画面を読みます。そのため起動時のプロンプトには、最終的な要約を画面上で読める程度に簡潔にまとめるよう指示しています。

### agent send / agent focus / agent close

job ID をそのペインに解決し、ペイン単位の `send`/`focus`/ `close-pane` の挙動をそのまま再利用します。途中で他のペインが開いたり閉じたりしていても、追加指示は常に意図した worker に届きます。

```bash
mytty-ctl agent send "$job" "回帰テストも追加して。" --enter
mytty-ctl agent focus "$job"
mytty-ctl agent close "$job"
```

```json
{ "type": "ok" }
```

`agent close` は job のペインを閉じ、非終端状態の job を `lost` に遷移させます。ユーザーがペインを閉じた、シェルが終了したなど、自然にペインが消えた場合も同じ扱いです。どの `agent` コマンドでも、`pane-not-found` ではなく `lost` として報告されます。

### guide

ペインチームの手順書(環境変数、split/send/wait/read の流れ、provider ごとの起動コマンド)をプレーンテキストで標準出力に出し、終了コード 0 で終わります。`MYTTY_CONTROL_SOCKET` も起動中の Mytty も不要です。このファイルはコマンド引数と JSON の形を説明する場所なので、手順の一次情報は `mytty-ctl guide` の出力そのものを見てください。`mytty-ctl --help`(`-h` や引数なしでも同じ)を実行すると、代わりに上のコマンド一覧が出ます。Mytty 本体はこれと同じ内容を起動のたびに `~/Library/Application Support/mytty/mytty-ctl.md` へ書き出しており、Claude Code / Codex 向けの「Agent に Mytty オーケストレーションの使い方を教える」設定はこのファイルへの参照を書き込みます([agent-providers リファレンス](agent-providers_ja.md) 参照)。

```bash
mytty-ctl guide
```

### list

開いている全ウィンドウの全ペインを一覧します。

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

`provider` は `AgentProvider.rawValue`( [エージェントイベントプロトコル](agent-event-protocol_ja.md)参照)、`agentState` は `AgentRunState.rawValue` です。そのペインにまだ1件もエージェントイベントが記録されていなければ、`null` にはならず、両方のキー自体が JSON から消えます(エージェント履歴の無いペインで実際に `mytty-ctl list | jq .` を実行して確認済み。`provider` も `agentState` も出力に現れません)。

### new-tab

アクティブウィンドウ(なければ最初に見つかったウィンドウ)に新規タブを作成します。特定のウィンドウを狙って指定する方法はありません。特定のウィンドウに作りたい場合は、そのウィンドウの既存ペインを `split` してください。

```bash
mytty-ctl new-tab --cwd /path/to/project
```

```json
{ "type": "pane", "paneID": "..." }
```

`--cwd` を省略すると、アクティブウィンドウの現在の作業ディレクトリを継承します。

### split

指定ペインを対象方向に分割します。分割対象のペインは、自動でフォーカスしてから分割します。

```bash
mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd /tmp
```

```json
{ "type": "pane", "paneID": "..." }
```

### send

ペインにテキストを送信します。`--enter` を付けると、続けて Enter も送ります。

```bash
mytty-ctl send "$paneA" "claude" --enter
mytty-ctl send "$paneA" "issue #42 を調査して" --enter
```

```json
{ "type": "ok" }
```

### send-key

単発のキーイベントを送ります。プレーンテキストでは反応しない対話的なプロンプト(矢印キーで選ぶメニュー、キャンセル用の `Esc` など)に使います。

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

`--modifiers` は `shift`、`control`、`option`、`command` からカンマ区切りで指定します(例: `--modifiers shift,command`)。未対応の `<key>` を渡すと、ペインが実在していても `pane-not-found` エラーになります。`ControlCoordinator` は「キーマッピングが無い」場合と「そのペインが無い」場合を区別せず同じ扱いにしているため、このケースに限りエラーコードの名前と実態が食い違います。この場合、キーイベントは送信されません。

```json
{ "type": "ok" }
```

### read

ペインの現在の画面テキストとカーソル位置を取得します。

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

カーソル位置を報告できない場合、`cursorRow` と `cursorColumn` は `null` になります。

### wait

対象ペインの直近のエージェント実行が条件を満たすか、タイムアウトするまでブロックします。

```bash
mytty-ctl wait "$paneA" --until idle
mytty-ctl wait "$paneA" --until attention --timeout-seconds 600
```

```json
{ "type": "waitResult", "state": "idle", "timedOut": false }
```

`--timeout-seconds` のデフォルトは `120` です。`state` は wait が解決した時点で観測された `AgentRunState`(そのペインに一度もイベントが来ていなければ `null`)です。`timedOut` は、タイムアウトまでに条件を満たせなかった場合に `true` になります。詳細は下記「wait の意味論」を参照してください。

### close-pane

確認ダイアログを出さずに、即座にペインを閉じます。呼び出し元は人間が Close をクリックしたのではなく、自動化されたエージェントである、という前提に立っています。

```bash
mytty-ctl close-pane "$paneA"
```

```json
{ "type": "ok" }
```

ウィンドウ内で最後のタブの最後のペインを閉じる場合、そのウィンドウ自体のクローズ確認ダイアログ(ユーザーが設定していれば)は依然として出ます。サブエージェント用に作ったペインでは、通常この状況は起きません。

### focus

指定ペインを前面にフォーカスします。制御をユーザーに戻したいときに使います。

```bash
mytty-ctl focus "$paneA"
```

```json
{ "type": "ok" }
```

## 失敗時のレスポンス

失敗したリクエストには、サーバーから `{"type":"failure","code":"..."}` が返ります。CLI 側はこれを JSON として印字せず、非ゼロの終了コードと標準エラーへのメッセージとして表現します。

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

`wait` は、条件を満たすかタイムアウトするまで、一定間隔(約300 ミリ秒)でポーリングします。

- `--until idle` は、対象ペインの直近のエージェント実行が `idle` / `succeeded` / `failed` / `disconnected` のいずれかになった時点で解決します。一度もエージェントイベントを受け取っていないペインは、タイムアウトするまでブロックし続けます。「まだ何も来ていない=idle 扱い」というデフォルトはありません。
- `--until attention` は、実行状態が `waiting-input` または `waiting-approval` になった時点で解決します。Antigravity の導入済み hook は承認・入力待ちイベントを一切出さないため([Agent providers](agent-providers_ja.md) 参照)、この provider が動くペインでは `wait --until attention` は常にタイムアウトします。Antigravity には `--until idle` を使ってください。Cursor も入力待ちイベントは出しませんが、承認待ちには到達しえます。mytty は Cursor の `preToolUse` hook と、対応する `postToolUse` / `postToolUseFailure` との間隔から、詰まった tool call を推定します。そのため、その推定が発火した時点(何も解決しなければ tool call 開始からおおよそ10秒後)で、Cursor ペインの `wait --until attention` も解決します。
- 対象 provider の hook 連携が設定でまだ有効化されていない場合、エージェントイベントが一切 Mytty に届きません。そのため条件に関わらず、`wait` はタイムアウトするまでブロックし続けます。provider を初めてスクリプトから使うときに想定外のタイムアウトが起きる、最もよくある原因がこれです。

`agent wait` も同じようにポーリングしますが、対象はペインではなく `agent spawn` が作った job です。条件も `wait`(`idle`/`attention`)とは異なる3種類(`running`/`attention`/`completed`)になります。詳細は上の [agent wait](#agent-wait) を参照してください。

## job のバインディング

`agent spawn` が作る job は、「そのペインが今やっていること」全般ではなく、特定の1つの worker 実行を指します。内部では `AgentJobTracker` が、新しいペインが作られた瞬間に既に存在する実行 ID の集合(新規ペインなので通常は空)を記録しておきます。その後、そのペイン/provider について観測した実行のうち、ID がその集合に含まれていない最初の実行に job をバインドします。一度バインドすると、job が別の実行に切り替わることはありません。これにより、連続して spawn した2つの job が互いの実行を誤って観測することはなく、`agent wait --until completed` が job より前から存在していた実行で解決してしまうこともありません。

job の状態は、バインドした実行の `AgentRunState` を直接マッピングしたものです。ステータスバーが使う `AttentionCenter` の「このペインで最も関連度の高い実行」というロジックは経由しません。両者は別の問いに答えています。30秒以内にどの実行もバインドできなければ、job は `launch-failed` になります(実行ファイルが無い、TUI が一度も起動しなかった、hook が一度も発火しなかった、のいずれもこれでカバーされます)。job のペインが消えたら、非終端状態の job は `lost` になります。どちらの遷移も後戻りしません。

job のレジストリは実行中のアプリのメモリ上にしかなく、永続化されません。Mytty を再起動すると、それより前に発行された job ID は `job-not-found` になります。job が指していたペインやプロセス自体は影響を受けず、その job ID からはもう辿れなくなるだけです。

## 制約・注意点

- `new-tab` はどのウィンドウに作るかを明示的に指定できず、アクティブウィンドウ(なければ最初に見つかったウィンドウ)に作られます。特定のウィンドウを狙いたい場合は、そのウィンドウの既存ペインを `split` してください。
- `close-pane` は確認ダイアログを出さずに即座に閉じます。唯一の例外(ウィンドウ内最後のタブの最後のペインを閉じる場合にウィンドウ自体の確認ダイアログが出るケース)は、サブエージェント用ペインの通常運用ではまず発生しません。
- pane ID は `TerminalSurfaceID` の UUID 文字列です。`list` のレスポンス、`pane` レスポンス、`$MYTTY_SURFACE_ID` のいずれかから取得します。
- control ソケットが受け付けるリクエストの最大サイズは、エージェントイベントソケットと同じ 64 KiB のエンベロープ上限に合わせてあります。非常に大きな `send` の引数は、1つの巨大なリテラルとして渡すのではなく、分割するか shell 経由でパイプしてください。`agent spawn` も、エンコード後のリクエスト(タスク本文 + 自動追記される worker contract)に対して同じ上限を接続前にチェックします。そのため、大きすぎるタスクはソケット書き込みが黙って失敗するのではなく、その場で CLI のエラーになります。
- `agent spawn` は既存ペインに worker を起動することは一切なく、必ず新しいペインを作ります。これは job のバインディングを正しく保つための前提(上の「job のバインディング」を参照)です。少数のペインを手動で管理する場合よりも、不要になった job を `agent close` で閉じることの重要性が増すということでもあります。
- job ID は `AgentJobID` の `{"rawValue":"..."}` 形式の UUID で、どの `agent` レスポンスでも `job.jobID.rawValue` から取得します。pane ID とは互換性がありません。

## 参考

- [mytty-ctl でエージェントのチームを動かす](../how-to/orchestrate-agents-with-mytty-ctl_ja.md): `agent` コマンドを使った複数worker の段階的な例を扱っています。
- [mytty-ctl アーキテクチャ](../explanation/mytty-ctl-architecture_ja.md): control ソケットが事前設定不要で動く理由と、`agent wait` を支える job/実行のバインディングの仕組みを説明しています。
- [Agent providers](agent-providers_ja.md): どの provider が承認・入力イベントを出すかをまとめています。`wait --until attention` に関係します。
- [エージェントイベントプロトコル](agent-event-protocol_ja.md): `list` と `wait` に出てくる `AgentProvider` と `AgentRunState` の値を定義しています。
- `.claude/skills/mytty-panes/SKILL.md`: これらのコマンドを使ったタスクレシピ集です。
