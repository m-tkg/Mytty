# アーキテクチャ

English version is [architecture.md](architecture.md).

このページは Mytty がなぜ今の形になっているかを説明する。端末エミュレーションを
libghostty に委譲し、その上にエージェント認識機能を重ねる。ワークスペースという
抽象も、チャット形式のオーケストレーション UI も持たない。

## Mytty とは何で、何でないか

Mytty は macOS 専用のネイティブ端末で、AI 支援ワークフロー向けに作られている。
端末エミュレーション、PTY 管理、Metal によるレンダリングを libghostty に委譲し、
その上にエージェント状態を認識する Attention Inbox を追加する。対応プロバイダーは
Codex、Claude Code、OpenCode、Gemini(Antigravity)、Cursor。

意図的に持たせなかったものが Mytty の性格を決めている。ワークスペースやプロジェクト
という実体、チャットパネル、アプリがエージェントを代わりに実行するオーケストレーション
エンジンはいずれも存在しない。エージェントはペインの中で動いている一つの
フォアグラウンドプロセスにすぎず、イベント経由で観測される対象であり、端末そのものが
主役であり続ける。この割り切りのおかげで、エージェントを一度も動かさないペインでも
アプリは普通に役立つし、各プロバイダーがすでに持っている「エージェントセッションとは
何か」というモデルと競合する二つ目のモデルを Mytty 側で維持する必要もなくなる。

## ユーザーモデル

オブジェクトの階層は意図的に浅い。

```text
Window
`-- Tab
    `-- SplitNode
        `-- TerminalSurface
            `-- AgentRun
```

Window の上にワークスペースという実体はない。カレントディレクトリ、Git ブランチ、
フォアグラウンドプロセス、エージェント状態はすべて端末サーフェス一つひとつが持つ
プロパティであり、それらをまとめる大きなプロジェクトオブジェクトは存在しない。これは
端末が実際に使われる様子をそのまま反映している。人はいま取り組んでいる作業のために
ペインを開くのであって、あらかじめ用意したプロジェクトのためにペインを開くわけでは
ない。縦タブがデフォルトで(横タブは設定で選べる)、複数ウィンドウとネストした分割も
サポートするが、`TerminalSurface` より上の層はそれらのペインが「なぜ一緒に存在するか」
を覚えようとはしない。

## UI の分担

AppKit と SwiftUI はそれぞれアプリの異なる領域を受け持ち、その境界線は
「精度が最も重要になる場所はどこか」で引かれている。

- AppKit がウィンドウ、メニュー、フォーカス、キーボードルーティング、IME、端末
  ホスト自体を持つ。キー入力のレイテンシと IME の正しさは SwiftUI の再描画サイクル
  に賭けてよいものではない。
- SwiftUI が Settings、タブサイドバー、Attention drawer を持つ。ここでは生の
  制御力よりも宣言的なレイアウトのほうが価値がある。
- 設定変更は、明示的に再起動が必要なものを除いて即座に反映される。ユーザーが
  設定画面をわざわざ後で見直しに来る必要がある場所にはしたくない。
- Attention drawer は右側から開き、フォーカスを奪うことも自分から開くこともない。
  バックグラウンドでエージェントが作業を終えたからといって、フォアグラウンドの
  ペインでユーザーがやっていることを中断できてはならない。

## ターゲットの境界

SwiftPM パッケージ(`Package.swift`)はこのアーキテクチャを慣習ではなく実際の
ターゲット境界として強制している。

- **`MyTTYApp`** が macOS アプリ本体。`TerminalWindowController` はウィンドウの
  ハブで、関心事ごとのコラボレーター(`AgentStatusPollingCoordinator`、
  `AgentUsagePollingCoordinator`、`RepositoryStatusCoordinator`、
  `PaneLayoutController`、`TerminalAutocompleteCoordinator`、
  `TerminalRecordingCoordinator`、`ScheduledInputCoordinator`、
  `RemotePaneBridge`、`TabDragController`)を保持し、それらの出力をサーフェスと
  ステータスバーに配線する。すべてを直接書き込む代わりにこの構成を取っている。
  `AppDelegate` もアプリ層で同じように委譲していて、メニュー構築は
  `MainMenuBuilder`、ウィンドウとセッションのライフサイクルは
  `WindowSessionCoordinator`、アップデート確認は
  `ApplicationUpdateCoordinator`、リモートアクセスサーバーのデリゲートは
  `RemoteAccessCoordinator` がそれぞれ受け持つ。神クラス化したコントローラーを
  名前付きのコーディネーターに分けているからこそ、それぞれの関心事を単体で
  テストでき、たとえばエージェント使用量のポーリングを変更してもペインレイアウト
  に触れずに済む。
- **`GhosttyAdapter`** は Ghostty の型に触れることが許された唯一のターゲット。
  libghostty はソースリビジョンを固定した上で XCFramework としてビルドされ、
  バージョニングされていない C API を持つため、そこへの呼び出しはすべてこの
  アダプター境界の内側に隔離されている。キーボード入力、IME、リサイズ、
  レンダリングはグローバルな SwiftUI や監視可能なアプリ状態を経由してはならない。
  これらの経路は libghostty 自体と同じくらい直接的で低レイテンシである必要がある。
- **`MyTTYCore`** は Foundation のみに依存するプラットフォーム非依存のロジックを
  持つ。タブ/セッションモデル(`TabSession`、`SessionSnapshot`)、エージェント
  イベントプロトコルとそのリデューサー、SQLite リポジトリ、プリファレンス、
  各プロバイダー固有の `*SessionInspector` / `*UsageProbe` の実装、そして
  `AgentSessionDatabase` がここに入る。Foundation のみに絞っているからこそ、
  AppKit 環境なしでテストを走らせられる。
- **`MyTTYAgentHook`** はプロバイダーのフックが呼び出すヘルパーバイナリ
  `mytty-agent-hook`。後述するソケット経由でイベントをアプリに転送する。
- **`MyTTYClamshellHelper`** は蓋を閉じたままスリープを防ぐために
  `pmset disablesleep` を実行する特権デーモン `mytty-clamshell-helper`
  (SMAppService/XPC)。そのステートマシン(`ClamshellHelperCore`)は
  `MyTTYCore` 側に置かれていて、特権ヘルパーを実際に動かさなくてもテストできる。
- **`MyTTYRemoteKit`** は iOS リモートアプリと共有するコード(ペアリング、
  セキュアチャネル)。

メニューコマンド、キーボードショートカット、CLI、`mytty-ctl` の制御ソケットと
いったすべてのエントリポイントは、それぞれ独自の状態変更経路を持つのではなく、
最終的に `TerminalWindowController` と `WindowSessionCoordinator` の同じ
アプリケーションレベルのコマンドを呼び出す。この収束があるからこそ、「メニュー項目
から開いたペイン」と「`mytty-ctl split` で開いたペイン」がずれることなく同じ
振る舞いをする。

## エージェントイベント: 画面をスクレイピングしない理由

エージェント状態は、明示的なフックか libghostty 自体の端末プロトコルサポートが
配信する、バージョン管理された冪等なイベントから導出される(ワイヤーフォーマットは
`docs/reference/agent-event-protocol.md` を参照)。人間可読な端末出力を解析して状態を推測することは
一切しない。これは「Waiting for approval」のような文字列をエージェントの CLI
出力から正規表現で拾うという、一見手軽な近道を最初から選択肢から外すということ
でもある。そうした文字列はプロバイダーのバージョンやロケールによって予告なく
変わるし、読み取りを誤れば Attention Inbox を無駄なイベントで埋めるか、逆に
本物の承認要求を静かに取りこぼすことになる。安定したスキーマバージョンを運べる
のはイベントだけだ。どの連携もイベントを報告していない場合は、推測せずに
`unknown` のままにする。

```text
unknown -> running
running -> waitingInput | waitingApproval | succeeded | failed
waitingInput | waitingApproval -> running
any -> disconnected
```

追記専用のイベントログが唯一の正となる情報源で、純粋なリデューサーがそこから
現在の実行状態を導出し、Attention ポリシーがその状態から実際に対応すべき
アイテムを導出する。リデューサーを副作用なし・隠れた状態なしの純粋な関数として
保つからこそ、上記の状態遷移は実際に動くアプリの中でしか壊れないものではなく、
入力と出力の対応表としてテストできる。

## Attention Inbox

Inbox が拾うイベントは承認要求、入力要求、失敗または切断、長時間実行タスクの
完了という 4 種類に限られる。ペインに関するそれ以外の情報、通常の出力や
進捗ログなどは意図的に外に出している。「まだ実行中です」まで報告するようになった
inbox は、もう確認する価値のあるものではなくなるからだ。

イベントはタブにバッジを付け、macOS 通知はそのタブが今見えていないときにだけ
飛ぶ。ペインを実際に見ているユーザーが同じイベントについて通知でも中断される、
という事態を避けるためだ。Inbox 上のアクションは Focus と Acknowledge に限られる。
プロンプトへの返信や要求への承認は端末そのものの中で行う。エージェントが実際に
見ている画面とずれうる二つ目の操作面をわざわざ作らない。解決済みのアイテムは
24 時間だけ保持され、あとから軽く振り返ることはできつつも Inbox が恒久ログに
なることは避けている。

## エージェント連携: フックだけに頼らない

Settings は各対応プロバイダー向けに、ワンクリックで元に戻せるフックの
インストールと削除を提供する。書き込み先はそのプロバイダー自身のグローバル設定
(`~/.codex/hooks.json`、`~/.claude/settings.json` など)で、インストーラーは
無関係な既存設定を保持したままアトミックに書き込む。ユーザーは自分自身の
プロバイダー設定を持ち込んでいるので、インストーラーが無関係なキーを壊したり、
クラッシュ時に中途半端なファイルを残したりする方が、イベントが届かないことより
はるかに悪い失敗モードになる。

フックはユーザー専用の Unix ソケット経由でイベントを送り、各ペインのフックは
そのペイン一つだけに閉じたケイパビリティを受け取る。入力の注入と画面キャプチャは
意図的に別のケイパビリティとして分けてあり、イベント用フックには付与されない。
そのため不正なフックスクリプトや誤動作するフックスクリプトも、状態を報告する
ことはできても端末を操作することはできない。

フックだけではステータスバーが見せたいすべてを網羅できないため、
`TerminalWindowController` の `AgentStatusPollingCoordinator` が 0.5 秒ごとに
各ペインのフォアグラウンドプロセスをポーリングして補っている。実行ファイルと
引数からプロバイダーを検出し(`TerminalAgentProcessDetector`)、そのプロバイダー
の `AgentProviderRuntime`(プロバイダーごとに一つ実装され、
`AgentProviderRuntimeRegistry` に登録されている)を解決し、そのプロバイダーの
`*SessionInspector` を通じて使用中のモデルと残りコンテキストを読み取る。Codex
のトランスクリプトのファイルディスクリプタ、Claude Code のプロジェクト
トランスクリプト、OpenCode と Cursor の SQLite データベース、Antigravity の
設定ファイルと、プロバイダーごとに読み取り方は異なる。これがメインスレッドで
動くため、毎ティック解析し直すのではなく、スロットリングとフィンガープリント
キャッシュ(`AgentSessionThrottleCache`)を挟んでいる。`AgentUsagePollingCoordinator`
も同じ構造で、`NativeAgentUsageLoader` と各プロバイダーの `*UsageProbe` に
対応する `AgentProviderUsageSource` レジストリを通じてクォータやコストの
メーターを読み込む。

これらのプローブが共通で使う読み取り専用 SQLite ヘルパーが `MyTTYCore` の
`AgentSessionDatabase` で、WAL データベースのサイドカーファイルがチェック
ポイントで消えている場合は `immutable=1` 接続にフォールバックする。プロバイダーの
SQLite 状態を読む必要があるコードはこのヘルパーを再利用する。WAL の
フォールバックはまさに一度ハマって二度目にまた同じ場所でデバッグしがちな
類の落とし穴だからだ。

## 設定と状態

ユーザー設定は UI から制御され、次の場所に保存される。

```text
~/.config/mytty/config.toml
~/.config/mytty/terminal.conf
~/.config/mytty/agents.toml
```

`terminal.conf` はそのまま libghostty に渡される。既存の Ghostty 設定の
インポートは明示的な一度限りの操作であり、Mytty がずっと同期を取り続けなければ
ならない暗黙の二つ目の情報源にはしていない。

実行時の状態は設定とは別の場所にある。

```text
~/Library/Application Support/mytty/mytty.sqlite
~/Library/Logs/mytty/mytty.log
$TMPDIR/mytty.sock
```

ウィンドウ、タブ、分割レイアウト、カレントディレクトリは再起動をまたいで
復元される。スクロールバックの永続化はオプトインでデフォルトは無効、
動作中の任意のプロセスは復元されない。デバッグビルドは **Mytty Dev** として
動き、上記すべてを `~/.config/mytty-dev/` とそれに対応する Application Support
/ ログの配下に隔離している。開発ビルドがインストール済みのリリース版の
セッションやソケットを一切乱さないようにするためだ。

## CLI と制御ソケット

同じアプリケーションコマンド群はローカル CLI とソケット API からも呼び出せる
(`mytty list --json`、`mytty tab new`、`mytty split --right`、
`mytty focus <surface-id>`、`mytty event emit <event>`、
`mytty config validate`/`reload` など)。これは、一つのペインで動く AI が
他のペインを目に見えて割り込み可能なチームとして操作できるようにする
AI 向け制御 CLI、`mytty-ctl` の土台でもある。ペアリングも暗号化も持たない
単純なローカルソケットとして作られている理由は
[mytty-ctl-architecture_ja.md](mytty-ctl-architecture_ja.md) を参照。

## 当初の設計から変わったこと

Mytty の当初の設計文書は、埋め込みブラウザをワークスペースオーケストレーション
や Inbox 内での返信と並んで初期の非目標に挙げていた。ブラウザペイン
(`BrowserPaneView.swift`)はその後実装された。ローカルの HTML や Web
コンテンツを端末と並べて見られる機能として十分に価値があると判断され、
別の概念としてではなく端末サーフェスと同じペイン/分割モデルの中に実装されて
いる。その他の非目標(ワークスペースオーケストレーション、Inbox 内での返信・
承認、エージェント状態の出力ヒューリスティック推測、永続 PTY デーモン、
クラウド同期)は執筆時点でも変わらず有効なままだ。当初の設計が示していた
段階的な提供計画、サーフェス単体の実証から始めてタブと永続化、エージェント
イベント、UI とフックインストーラー、CLI とパッケージングへと進む流れは
すでに一通り完了している。上のセクション群はその計画がどこへ向かっている
かではなく、どこに着地したかを説明したものだ。
