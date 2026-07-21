# Agent providers リファレンス

Mytty は5つの agent provider に対応する。コード上は `AgentProvider`
(`Sources/MyTTYCore/AgentEvent.swift`)で `codex`、`claude-code`、
`opencode`、`antigravity`、`cursor` として識別される。このページは
provider ごとに、Mytty が hook を書き込む設定ファイル、その provider の
hook が発行できる mytty event kind、セッション再開(resume)の仕組みを
列挙する。イベント自体のワイヤーフォーマットは
[エージェントイベントプロトコル](agent-event-protocol_ja.md) を参照。

Antigravity provider は、1つの event カテゴリの下に2種類の実行バイナリ
をまとめている。`AgentProvider.antigravity` は Google Antigravity IDE の
エージェントと、スタンドアロンの Gemini CLI の両方を指す単一の
プロトコル上のカテゴリで、hook イベントとしては両者を区別しない。両者が
分岐するのはセッション再開(resume)の場面で、Mytty はフォアグラウンド
プロセスの実行バイナリの basename を見て、Gemini CLI らしければ
(basename が `gemini` または `gemini-cli`、あるいはパスに
`/gemini-cli/` を含む)`gemini --resume=<id>` を、そうでなければ
`agy --conversation=<id>` を選ぶ
(`Sources/MyTTYApp/AgentSessionRestoration.swift` の
`AgentResumeLaunchPlan.isGeminiCLI`)。アプリ内の一部表記や過去の
ドキュメントはこれを「Gemini (Antigravity)」と短縮しているが、この表記
は provider 名であって resume コマンドを表すものではない。

## 設定ファイルと handler

hook helper の共有バイナリは
`~/Library/Application Support/mytty/bin/mytty-agent-hook` に置かれる。
**設定 > Agents** で provider を有効化すると次のファイルが書き換わる。

| Provider | 設定ファイル | 書き込まれる内容 |
| --- | --- | --- |
| Codex | `~/.codex/hooks.json` | prompt、permission、post-tool、stop イベント用の command handler |
| Claude Code | `~/.claude/settings.json` | prompt、permission、post-tool、notification、stop、failure イベント用の command handler |
| OpenCode | `~/.config/opencode/plugins/mytty.js` | mytty 専有の global plugin ファイル1つ |
| Antigravity | `~/.gemini/config/plugins/mytty/` | invocation と stop hook を持つ mytty 専有の plugin ディレクトリ1つ |
| Cursor | `~/.cursor/hooks.json` | prompt、pre-tool、post-tool、stop イベント用の command handler |

Codex、Claude Code、Cursor の設定は JSON で、構造的にパースしてから
atomic に書き戻す。無関係なトップレベルの値、matcher グループ、handler
はそのまま残る。削除時は、mytty 自身の helper パスを該当する provider
引数付きで呼んでいる handler だけを取り除く。OpenCode の無効化は
`mytty.js` だけを削除し、Antigravity の無効化は mytty の plugin
ディレクトリだけを削除する。壊れた JSON は決して上書きされない。
設定画面はその provider の設定を invalid として報告し、ファイルはその
まま残す。

各 provider の設定画面の行は、トグルを押したかどうかではなく実際の
ファイルの中身から **Installed** / **Needs Repair** / **Not Installed**
を導出する。手で編集された、あるいは部分的に削除されたインストールは
**Needs Repair** と表示される。

**Teach agents about pane teams**(Settings > Orchestration、デフォルトオン)は、
グローバルなポインタの置き場所が確認できている2つの provider に対して、
上記とは別のファイルを書き込む。

| Provider | ファイル | 内容 |
| --- | --- | --- |
| Claude Code | `~/.claude/skills/mytty-panes/SKILL.md` | Mytty が全体を所有する user skill |
| Codex | `~/.codex/AGENTS.md` | `<!-- mytty:pane-team:begin -->` / `:end` の管理ブロック。ブロックの外側は一切触らない |

どちらも中身を複製せず `mytty-ctl guide` を指すだけなので、Mytty が
アップデートされても手直しなしで正確な内容を保つ。Cursor・OpenCode・
Antigravity はグローバルな指示の置き場所がまだ確認できていないため対象外。

## Lifecycle マッピング

mytty の1 agent run は1プロンプトまたは1ターンを表し、長時間続く CLI
セッション全体は表さない。そのため直前の run が完了すると新しい
プロンプトで新しい run が始まる。

| mytty event | Codex | Claude Code | OpenCode | Antigravity | Cursor |
| --- | --- | --- | --- | --- | --- |
| `started` | `UserPromptSubmit` | `UserPromptSubmit` | user `message.updated` | 非対応 | `beforeSubmitPrompt` |
| `approval-requested` | `PermissionRequest` | `PermissionRequest` または permission notification | `permission.asked` / `permission.updated` | 非対応 | 推定(下記参照) |
| `input-requested` | input 系の permission tool | input notification または `AskUserQuestion` | `question.asked` | 非対応 | 非対応 |
| `running` | `PostToolUse` | `PostToolBatch` | `permission.replied` | `PreInvocation` / `PostInvocation` | `preToolUse` / `postToolUse` / `postToolUseFailure` |
| `succeeded` | `Stop` | `Stop` | `session.idle` | idle 時の `Stop` | `completed` を伴う `stop`、または `status` フィールド自体が無い `stop` |
| `failed` | 導入済み hook では非対応 | `StopFailure` | `session.error` | error 時の `Stop` | `error` を伴う `stop` |
| `disconnected` | 非対応 | 非対応 | 非対応 | 非対応 | `aborted` を伴う `stop` |

Antigravity の導入済み hook は lifecycle と結果の status しか提供しない。
`approval-requested` や `input-requested` は一切発生しないため、この
provider が動くペインでは `mytty-ctl wait --until attention` が解決しない
([mytty-ctl リファレンス](mytty-ctl_ja.md) 参照)。

Cursor にも permission prompt 専用の hook は無いが、mytty はあらゆる
tool call の前に発火する `preToolUse` からそれを推定する — シェル
コマンドに限らず、ファイルの編集や削除も承認プロンプトの対象になる。
`preToolUse` はその tool call の `tool_use_id` を key に10秒のタイマーを
開始し、同じ `tool_use_id` を持つ `postToolUse` / `postToolUseFailure`、
またはその run の `stop` が先に届けばタイマーはキャンセルされる。
tool call は同時に複数走ることがある — 実機で、異なる2つのツールの
`preToolUse` が連続して届き、どちらの `postToolUse` もまだ来ていない
状態が観測されている — そのため pending タイマーは run 単位ではなく
`tool_use_id` 単位で追跡する。run 単位にすると、同じ run 内の別の
tool call が解決した瞬間に、まだ pending な tool call を見失って
しまうため。時間内に何も届かなければ、mytty 自身が
`approval-requested` event を合成する — pending 状態は
`CursorApprovalPendingTracker` が保持し、タイマーは
`CursorApprovalCoordinator`
(`Sources/MyTTYApp/CursorApprovalCoordinator.swift`) が持ち、event 自体は
`AgentHookEventAdapter.pendingApprovalEvent` が組み立てる。その後
一致する `postToolUse` または `postToolUseFailure` が届けば、実際の
approval が解決する場合と同じ経路で run は `running` に戻るため、
解決処理を別途書く必要はない。10秒以内に終わる自動承認 tool call は
そもそも発火しない。自動承認だが実行が長引いた tool call は、一時的に
Attention に `approval-requested` として出た後、その `postToolUse` が
届いた時点で自動的に解決する。

mytty はもう Cursor の `beforeShellExecution` / `afterShellExecution`
hook にハンドラを導入せず、承認待ちの検知にも使わない: この2つは
シェルコマンドしか挟まないため、非シェルの tool call(実機で観測された
ファイル削除の承認待ちなど)が承認プロンプトで詰まってもどちらの hook も
発火せず、これに基づく遅延推定は取りこぼしていた。この2つの hook の
マッピング自体は、手動でこれらを導入した人のために引き続き認識される
が、設定画面から Cursor 連携をインストール・修復すると、今後は
`preToolUse` が書き込まれる。

provider ネイティブの識別子は次のように mytty の run 識別子へ変換
される: Codex の `turn_id`、Claude Code の `prompt_id`、OpenCode の
現在のユーザーメッセージ ID、Antigravity の `conversationId`、Cursor の
`generation_id`。hook のペイロード自体が保存されたり、人間が読む
ターミナル出力から解析されたりすることはない。

## Status bar のセッション識別子

status bar が表示するセッション識別子は、provider ごとに別の情報源から
取得する。

| Provider | 情報源 |
| --- | --- |
| Codex | フォアグラウンド PID に紐づく transcript。取得できなければ hook event の値にフォールバック |
| Claude Code | hook の `session_id` |
| OpenCode | hook の `sessionID` |
| Antigravity | hook の `conversationId` |
| Cursor | hook の `conversation_id`、または Cursor CLI の `session_id` エイリアス |

Claude Code はユーザーが Esc でプロンプトを中断しても hook を発行しない
ため、特別な処理が無ければ run が `running` のまま残り続ける。poller は
すでに読んでいる transcript からこれを検出する: 直近の `promptId` の
最後の行が `interruptedMessageId` を持っていれば、その `promptId` を
key にして `idle` event を合成し、hook が作った run にそのまま乗せる。
このイベントの identity には `interruptedMessageId` も含まれるため、
同じ中断を再読み込みしても no-op になり、同じプロンプトの2回目の中断は
別イベントとして run を終了させる。

## モデル名とコンテキストメーターの情報源

status bar のモデル名と(取得できる場合の)残りコンテキストメーターは、
hook のペイロードではなくローカルの transcript から、provider ごとの
`*SessionInspector`(`Sources/MyTTYCore`)経由で取得する。

| Provider | Inspector | 情報源 | コンテキストウィンドウ |
| --- | --- | --- | --- |
| Codex | `CodexSessionInspector` | フォアグラウンド PID に紐づく transcript の `turn_context.model` と最新の `token_count.info` | transcript が報告する値 |
| Claude Code | `ClaudeCodeSessionInspector` | `~/.claude/projects/<session-id>.jsonl`(複数の project ディレクトリを横断検索)、hook session ID が無い場合は `~/.claude/projects/<slug>/` 配下で最も新しく更新された transcript。最後の `assistant` 行の `message.model`、トークン数は `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` の合計 | `[1m]` モデルは 1,000,000、それ以外は 200,000 |
| OpenCode | `OpenCodeSessionInspector` | `opencode.db` の `message` テーブル、hook session ID に対応する最新の assistant 行の `modelID` | ローカルでは取得不可 |
| Cursor | `CursorSessionInspector` | `~/.cursor/chats/<workspace-hash>/<session-id>/` 配下の chat ディレクトリ(hook session ID、または `cwd` がペインと一致する最新の `meta.json`)。`store.db` の `blobs` テーブルを新しい順に、`providerOptions.cursor.modelName` をテキストスキャン | ローカルでは取得不可 |
| Antigravity | `AntigravitySessionInspector` | `~/.gemini/antigravity-cli/settings.json` の global な `model` 設定。セッションに紐づかない値なので、無関係なペインに誤帰属させないよう hook session ID が無いと何も表示しない | ローカルでは取得不可(会話 DB は protobuf エンコードで安定したスキーマが無い) |

Claude Code の `<slug>` は作業ディレクトリのパス中の英数字以外の文字を
すべて `-` に置き換えたもの。0.5秒間隔のフォアグラウンドポーリングを
軽く保つため、Claude Code の transcript 読み取りは追跡している
`(mtime, size)` の fingerprint が変化したときだけ行う。OpenCode、
Cursor、Antigravity のルックアップは pane ごとの共有 cache を持ち、
5秒に1回にスロットリングされ、hook session ID が変わった時点で即座に
無効化される。

## Session restoration(resume コマンド)

**On Launch** が **Restore last session** のとき、mytty はセッション
スナップショット保存時にペインで動いていたエージェントを、次のいずれか
のコマンドを再開後のシェルの初期入力として送ることで復元する。

| Agent | Resume コマンド |
| --- | --- |
| Codex | `codex resume -- <session-id>` |
| Claude Code | `claude --resume=<session-id>` |
| OpenCode | `opencode --session=<session-id>` |
| Gemini CLI | `gemini --resume=<session-id>` |
| Antigravity CLI | `agy --conversation=<session-id>` |
| Cursor | `cursor-agent --resume=<session-id>` |

Gemini CLI と Antigravity CLI はどちらも `AgentProvider.antigravity` を
共有しており、どちらの resume コマンドを選ぶかは別の provider 値では
なく、スナップショット時点のフォアグラウンドプロセスの実行バイナリの
basename で決まる(`Sources/MyTTYApp/AgentSessionRestoration.swift` の
`AgentResumeLaunchPlan.kind`)。

resume メタデータは、まだ動作中でセッション識別子が既知のエージェント
プロセスからのみ再生成され、一度使われると消費される。エージェント
終了後は残らない。セッション識別子は長さをチェックされ、制御文字を
含む場合は拒否され、復元先のシェルに渡す前に POSIX quote される。

## 参考

- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [OpenCode plugins](https://opencode.ai/docs/plugins/)
- [Antigravity hooks](https://www.antigravity.google/docs/hooks)
- [Antigravity plugins](https://www.antigravity.google/docs/plugins)
- [Cursor hooks](https://cursor.com/docs/hooks)
