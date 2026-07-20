[English](README.md)

# Mytty

**はじめての方は[使い方ガイド](docs/usage_ja.md)から** — スクリーンショット付き
で、最初に触れる操作をまとめています。

## 概要

Mytty は AI を使う開発作業に合わせた、Apple Silicon 専用の macOS
ネイティブターミナルです。Metal によるターミナル描画には libghostty、
周辺 UI には AppKit、SwiftUI、WebKit を使用しています。ターミナルを主役に
したまま、タブ、ペイン、Agent の状態表示、通知パネル、作業用ツールを追加し、
workspace のような別の管理概念は導入しません。

Codex、Claude Code、OpenCode、Gemini (Antigravity)、Cursor に対応しています。
各連携は pane ごとの Unix socket へ構造化イベントを送り、人向けのターミナル
出力を解析せずに、要求元の pane と Agent の状態を対応付けます。

現在のリリースは macOS 15 以降、Apple Silicon に対応しています。

## 特徴

- **Ghostty のターミナルエンジン:** libghostty による描画、ネイティブ IME、
  theme、フォント、カーソル、透明度、ライト・ダーク表示の設定。
- **シンプルなタブと pane:** 4 方向分割、タブのドラッグ並べ替え、pane の
  全体表示、均等配置、タブパネルの配置変更、すべての pane の切り替え画面。
- **コマンドパレット:** Command-Shift-P で全メニューコマンドを検索できる
  パレットを開き、入力で絞り込み(あいまい一致対応)、Return で実行。
- **Agent 対応ステータス:** Agent 名、セッションコスト、取得できる場合の
  利用量メーター、処理状態、GitHub repository と branch、作業フォルダ、
  sleep 防止、日時指定入力を表示。
- **通知パネル:** 承認、入力、完了、失敗のイベントを保存し、発生元の pane
  へ直接移動。
- **AI からの操作(`mytty-ctl`):** 設定不要でどの pane からでも使える
  ローカル CLI。AI エージェントが pane の作成・分割、テキスト送信、画面読み
  取り、別 pane のエージェントが idle/要対応になるまでの待機ができ、複数
  pane にまたがるサブエージェントのチームを実際に見える pane として動かせる。
- **セッション復元:** window、tab、terminal/browser pane、分割比率、CWD、
  再開可能な Agent session を復元。
- **ローカル autocomplete:** shell 履歴と、成功した `mkdir` に対する `cd`
  候補を薄く表示し、Tab で確定。
- **アプリ内ブラウザ:** ローカル HTML と Web、pane 内検索、外部 browser・
  tab・pane・clipboard を選べるリンク操作。
- **iOS リモート:** ローカルネットワークで iPhone をペアリングし、Mac の色の
  まま pane を表示・入力。日本語は iPhone 側で漢字変換してから送信し、切断状態も
  明確に表示。Attention は APNs でプッシュされ、リモート app が終了していても
  iPhone に通知が届く。
- **GIF 録画:** 最大 60 秒、Retina 解像度で pane を録画し、停止後に保存先を
  選択。
- **ネイティブ設定画面:** 日本語・英語、keybinding の競合検出、終了確認、
  起動動作、署名を検証するアプリ内 update。

## 機能説明

### Window、tab、pane

window、tab、pane をそのまま使い、workspace はありません。タブパネルは左、
右、上、下に配置できます。タブのどこからでもドラッグして並べ替えられます。
右クリックメニューから、名前変更、path のコピー、Finder 表示、上下移動、
終了、pane の均等配置を実行できます。terminal pane 自体の右クリックメニュー
からは、その pane を閉じられます。pane 数は常に表示され、全体表示中、
録画中、Agent の処理中も tab のアイコンで確認できます。macOS 26 以降では
名前変更ダイアログに**自動で命名**ボタンが付き、オンデバイスの Apple
Intelligence モデルがフォーカス中の terminal の最近の出力を読んで短い名前を
入力欄に提案します。内容が Mac の外に送られることはなく、確定は Save を
押したときだけです。

分割すると、フォーカス中の pane が半分に分かれます。境界をドラッグして比率を
変えられるほか、**ペインを均等に配置**で領域を均等化し、**ペインを全体表示**
で現在の pane だけを一時的に広げられます。**ペインを入れ替え**(Window ▸ Pane メニュー、
Control-Command-S)を実行すると、クリックで tab の pane 配置を組み替えられます。
最初にクリックした pane はアクセントカラーの枠でハイライトされ、ステータス
ヒントが2つ目の選択を案内します。2つ目の pane をクリックすると、分割比率を
保ったまま2つの pane の位置が入れ替わります。同じ pane を再度クリックするか、
コマンドをもう一度実行するとキャンセルできます。ペインを入れ替えモード中は、
矢印キーだけでも操作できます。上下左右キーで薄い枠のカーソルを pane 間で移動し、
Return キーでクリックの代わりにカーソル位置の pane を決定します。macOS 26 以降では **ペインを解説**
(Window ▸ Pane メニュー、Control-Command-I)で、オンデバイスの Apple Intelligence
モデルがフォーカス中 terminal の最近の出力を読み、この pane で何が起きているか
をフローティングパネルで解説します(内容が Mac の外に出ることはありません)。
**実行結果を要約**(Window ▸ Pane メニュー、Control-Command-J)は最後に実行した command
に絞った機能で、結果を数値・パス・名前などの具体情報を保ったまま詳しく要約し、
エラーが出ていた場合は各エラーの意味・原因・修正案まで解説します。
非アクティブな pane は暗くなり、
カーソルの blink も停止します。window または pane の resize 中は、各 pane
の文字グリッド数を一時表示します。

**すべてのペインを表示**では、現在の command または Agent 名と CWD を一覧に
します。行を選ぶと該当 tab へ移動し、その pane にフォーカスします。

pane や tab を閉じても、そのセッション中は内容が保持されます。
**閉じた項目を開き直す**(Window メニュー、Command-Shift-T)で直近に閉じた
pane・tab を、スクロールバック・作業ディレクトリ・Agent の resume 情報ごと
復元でき、**最近閉じた項目**サブメニューからは直近20件までを個別に選んで
復元できます。この履歴はメモリ内のみで、Mytty 再起動時の復元対象には含まれず、
window を閉じても記録されません。

### Shell と autocomplete

terminal pane は保存された CWD で login shell を起動します。shell、font、
font size、cursor の形と blink、表示モード、Ghostty theme、独自の文字色・
背景色・透明度は **設定 > Shell** から変更でき、開いている pane に即時反映
されます。font 一覧では各 font 名をその font で描画し、macOS が言語別の名前を
持っている場合は設定言語に合わせて表示します。

プログラミング用の合字は既定で無効にしており、terminal は文字をそのまま表示
します(`->` が `→` の glyph になりません)。有効化やカスタマイズをしたい場合は
`~/.config/mytty/terminal.conf` に自分で `font-feature` を書きます(例:
`font-feature = calt`)。Mytty は font-feature が未設定のときだけ既定値を補います。

autocomplete は、入力して実行した command の履歴をローカルで学習します。
また、`mkdir <directory>` が成功すると `cd <directory>` を候補にします。
薄く表示された候補は Tab で確定でき、通常の編集をすると消えるか更新されます。
Shell 設定から無効にできます。

macOS 26 以降では **ワンライナー作成**(編集メニュー、Control-Command-K)で、
「フォルダ内のファイルで、中に "Test" が含まれているものを探したい」のような
自然言語の依頼を、オンデバイスの Apple Intelligence モデルが shell の
ワンライナーに変換します。結果は読み取り専用で表示され、隣のコピーボタンで
clipboard にコピーします(実行はされません)。1つの command で実現できない
場合は、モデルがその旨を返します。内容が Mac の外に出ることはありません。

### Agents と通知

**設定 > Agents** で provider ごとに連携を導入します。Mytty は provider の
無関係な設定を残したまま hook を追加し、導入済み連携の修復もできます。hook
は Mytty pane の外では何も送らないため、別の terminal で同じ Agent を使っても
Mytty の event socket は必要ありません。

アクティブ pane の Agent 名は title/status 領域に表示されます。provider から
取得できる場合は、コンパクトな meter 上に残量 % を重ね、推定 session cost も
表示します。Agent 情報をクリックすると、session ID が分かっている場合に
**Copy Session ID** を選べます。回転アイコンは Agent が処理中のときだけ表示し、
prompt で入力を待っている間は表示しません。

通知パネルには承認要求、入力要求、完了、失敗を保存します。タブパネルまたは
shortcut から開き、return 形のボタンで発生元 shell に移動できます。ヘッダーの
一括クリアボタンで未読をまとめて既読にできます。該当 pane
へ移動すると通知は既読になり、見ている最中の pane からのイベントは最初から
既読で届きます。つまり未読は「他の tab・pane で完了・要求されたもの」だけに
なります。接続・切断自体は通知に表示しません。

**Agent 使用中のスリープ防止**には3段階の設定があります: 常に sleep する、
Agent がターンを実行中だけ sleep しない、Agent の CLI が pane で起動している
間はターンの合間も含めて sleep しない、の3つです。選択した条件を満たす間だけ
Mytty が sleep を防ぎます。この assertion は system sleep だけでなく
**ディスプレイのスリープ**も抑止します。見やすさのためではなく、libghostty が
各 surface の描画ループを display link 上に構築しており、起きているディスプレイ
が 1 つも無いとその生成に失敗するためです。画面がスリープした Mac では window・
tab・pane のいずれも開けなくなります。status bar の月・太陽アイコンは現在の
モードと状態を表し、hover で説明を表示し、click するとモードを選ぶメニューが
開きます。スリープ防止が効いている間は、**蓋を閉じた場合のスリープ**も併せて
抑止します: 外部モニタのない MacBook では蓋を閉じると assertion では防げない
強制スリープになるため、同梱の特権ヘルパーが防止条件の成立中だけシステム全体の
スリープを止め、条件が終われば(Mytty がクラッシュした場合も自動で)元に戻し
ます。ヘルパーはシステム設定で Mytty のバックグラウンド項目を一度だけ許可すれば
動作し、パスワード入力は不要です。防止モードを選ぶとまず説明ダイアログを表示し、
了承した場合にだけシステム設定を開きます。未許可の間は tooltip にも許可方法を
表示します。
蓋クローズ抑止の有効中は status bar のアイコンがオレンジ色になり、tooltip にも
その旨を表示します。

### AI からの操作(mytty-ctl)

`mytty-ctl` は、Mytty の pane 内で動く AI エージェントが Mytty 自身を操作
するためのローカル CLI です。pane 一覧の取得、pane の作成・分割(特定の作業
ディレクトリ、例えば別の `git worktree` を指定可能)、テキスト送信や単発キー
送信、画面テキストの読み取り、対象 pane のエージェント実行が idle や要対応に
なるまでの待機、pane を閉じる・フォーカスする、が行えます。Mytty の全 pane の
shell には `MYTTY_CTL_BIN`(バイナリのパス)と `MYTTY_CONTROL_SOCKET` が自動で
設定されるため、Mytty が起動している以外の準備は不要です。

これにより「サブエージェントのチームを動かす」がスクリプト化可能なパターンに
なります: AI が pane を分割し(pane ごとに Claude Code / Codex / Cursor など
provider を変えてもよい)、それぞれでエージェントを起動し、並行して完了を待ち、
結果を回収する — すべて人間が見たり割り込んだりできる、見えない裏で動く
サブエージェントとは違う、通常の pane として行われます。コマンドリファレンス
とアーキテクチャ、具体例は `docs/mytty-ctl.md` を、すぐ使えるレシピは同梱の
`mytty-panes` スキルを参照してください。制御ソケットはローカル限定かつ
無認証で、Unix のファイルパーミッション(`0600`)のみで同一ユーザーに保護
されています — CGEvent など他の同一ユーザー自動化と同じ信頼境界です。

### Status bar と日時指定入力

status bar は設定で非表示にできます。左側には GitHub と folder、右側には
Agent、sleep 防止、日時指定入力を配置します。GitHub repository 内では GitHub
ボタンから remote repository を開け、隣に現在の branch 名を表示します。
folder ボタンはアクティブ pane の CWD を Finder で表示します。

時計メニューから、アクティブ pane に送る日時、文字列、末尾に改行を付けるかを
設定できます。登録済みの内容は同じメニューから編集・削除できます。過去または
実行済みの設定は消去され、pane を閉じた場合も削除されます。指定時刻に Mytty が
起動していなければ何も実行しません。

### アプリ内ブラウザとリンク

Command-O でローカル HTML を開きます。browser pane には navigation、検索、
閉じる操作があります。Control-F はフォーカス中の terminal または browser
pane を検索します。リンクを Command-click すると、**Open in browser**、
**Open in new tab**、**Open in new pane (right)**、**Open in new pane (down)**、
**Copy link** から動作を選べます。表示文字列と URL が異なるハイパーリンクや、
Claude Code のようにマウスをキャプチャするフルスクリーンアプリの表示中でも
同じように動作します。

### 録画と入力キー表示

**録画を開始/停止**で、フォーカス中の pane を GIF にします。60 秒で自動停止し、
停止後に保存先を尋ねます。録画中は tab に停止ボタンを表示します。**押されたキー
を pane に表示**を有効にすると、通常時は cursor の下にキー名を表示し、録画にも
同じ位置で含まれます。

### iOS リモート

**設定 > iOS Remote Access** を有効にしてペアリングコードを生成し、companion
iOS アプリ(`ios/MyttyRemote`)をローカルネットワークでペアリングします。Mac は
Bonjour で見つかり、接続はペアリング済みで暗号化されます。Mac はポート 51820
で待ち受けます(使用中の場合は自動ポートに切り替わり、実際のポートは設定画面に
表示)。Tailscale などの VPN 経由ではアドレスを直接入力してペアリングできます。
ペアリング試行はキャンセルでき、30秒で自動的にタイムアウトします。iPhone からは window・
tab・pane を辿り、pane を開くとライブ表示できます。pane は Mac の terminal の色
(bold・dim・反転表示を含む)で描画され、block cursor も出ます。scrollback は
最大 10,000 行まで iPhone 側へ反映されます。新しい出力への
追従は最下部にいる間だけなので、scrollback を遡って読んでいる位置は画面更新で
動きません。全画面型のターミナルアプリ(Agent、pager、editor など)には
scrollback が存在しないため、そうした pane でのスクロール操作は Mac 側へ
ホイール入力として転送され、アプリ自身のスクロール(Agent の履歴表示など)を
iPhone から操作できます。入力は pane に送られ、日本語は iPhone の IME で変換(漢字変換は端末側で行い、確定した文字だけ
送信)します。Ctrl・Option・矢印などの名前付きキーはコントロールキーバーから
送れます。バーの貼り付けキーは iPhone のクリップボードをペーストとして pane に
送り、pane のツールバーのコピーボタンはバッファのスナップショットを固定表示
する画面を開いて、iOS 標準の選択操作でテキストを選択してコピーできます
(**Copy All** で全文コピーも可能)。接続が切れると pane にバナーを表示し、古い内容を薄くして、**Reconnect**
をタップするまで入力を無効化します。アプリがフォアグラウンドに戻ったときは
自動で再接続します。どちらの場合も同じ pane に留まり、その間に Mac 側で pane が
閉じられていれば pane 一覧へ、tab ごと閉じられていれば tab 一覧へ戻ります。
ブラウザ pane を開くとタイトルとページの現在の URL を表示し(Mac 側の遷移に
追従して更新)、同じページを iPhone のアプリ内 Safari で開くボタンと URL の
コピーボタンを備えます。登録
済みの Mac は iPhone 側の設定画面から後で編集でき、ラベルに加えて接続方法
(Bonjour サービス名、または手動のホストとポート)も再ペアリングなしで変更
できます。

#### プッシュ通知

Attention は Apple Push Notification service 経由でペアリング済みの iPhone にも
届きます。席を外している間にエージェントが承認を求めた場合、リモート app が
終了していても iPhone に通知されます。送信されるのは Mytty が最前面でないとき
だけで、pane が画面上でフォーカスされたままのケース(実行中のエージェントを
置いて離席した状況そのもの)も含みます。そのため Mac 側のバナーと二重に鳴る
ことはありません。

中継は Cloudflare Worker
(`cloudflare/push-relay`) が担うため、この Mac 側での設定は不要です。iPhone が
Worker に直接登録し、Mac にはその handle だけが渡されます。

通知本文が平文で中継に届くことはありません。Mac がペアリング時に確立した鍵で
封をし、iPhone 側の notification service extension が iOS の表示直前に開きます。
Cloudflare から見えるのはデバイストークン・ランダムな Mac 識別子・暗号文だけ
です。復号できない場合は Attention の種別のみを示すプレースホルダーが表示され
ます。

通知をタップすると、その Attention を出した pane がアプリで開きます。対象の Mac
に接続し、window と tab をたどって pane まで移動します。その pane が既に閉じて
いる場合は、その Mac のセッション画面で止まります。

ペアリングを解除せずにプッシュだけ止めたい場合はトグルをオフにします。Worker
を自分でホストする方法(自分の Apple Developer チームで iOS app をビルドする
場合は必須)は
[`cloudflare/push-relay/README.md`](cloudflare/push-relay/README.md) を参照して
ください。

### 設定と保存場所

設定カテゴリは **General**、**Shell**、**Agents**、**Key Bindings**、**Update**
です。keybinding は UI から入力でき、競合時は相手の command を表示します。
入力中に Delete を押すとその割り当てを削除できます。

release 版のデータ保存先は次のとおりです。

| データ | 保存先 |
| --- | --- |
| アプリ設定 | `~/.config/mytty/config.toml` |
| ターミナル設定 | `~/.config/mytty/terminal.conf` |
| Agent 設定 | `~/.config/mytty/agents.toml` |
| Session、event、日時指定入力 | `~/Library/Application Support/mytty/` |
| Log | `~/Library/Logs/mytty/` |

ローカルの debug 実行は明確に分離されます。`swift run Mytty` は **Mytty Dev**
という名前と Dock の `DEV` badge で表示され、`mytty-dev` の各 directory と
`com.m-tkg.mytty.dev` socket を使います。導入済み release と同時に起動しても、
設定、session、利用量 cache は共有しません。provider の設定自体は global な
ため hook の導入だけは共有しますが、event の送信先は pane ごとに分かれます。

### デフォルト shortcut

すべて **設定 > Key Bindings** から変更または削除できます。

| 操作 | デフォルト shortcut |
| --- | --- |
| 設定 | Command-, |
| 新規 window / tab | Command-N / Command-T |
| Tab 名の変更 / tab を閉じる | Command-R / Command-W |
| 閉じた項目を開き直す | Command-Shift-T |
| 右 / 下に分割 | Command-D / Command-Shift-D |
| Pane のフォーカス移動 | Command-Option-矢印 |
| Pane を均等に配置 | Control-Command-= |
| Pane の全体表示を切り替え | Control-Command-Return |
| ペインを入れ替え | Control-Command-S |
| Pane 内を検索 | Control-F |
| すべての pane を表示 | Control-Command-P |
| コマンドパレット | Command-Shift-P |
| Pane を閉じる | Command-Shift-W |
| 通知パネルを切り替え | Command-Shift-A |
| Tab パネルを切り替え | Command-B |
| 録画を開始/停止 | Command-Shift-G |
| ペインを解説(macOS 26+) | Control-Command-I |
| 実行結果を要約(macOS 26+) | Control-Command-J |
| ワンライナー作成(macOS 26+) | Control-Command-K |

### Update

起動時と About 表示時に GitHub Releases を確認します。新しい署名済み release は
**About Mytty** または **設定 > Update** から確認・導入できます。自動確認と
通常クリックの **Check for Updates** は stable release のみを対象とし、
option を押しながら **Check for Updates** をクリックすると pre-release
(`x.y.z-beta.1`、`x.y.z-rc.2` など)も対象にして、見つかった最新のものへ
update できます。置換前に、download の digest、bundle ID と version、
Developer ID の team 署名、内包 code、Gatekeeper の判定を検証します。
Mytty Dev では自動・手動 update を無効にします。

## ビルド方法

> **iOS リモート app を自分のアカウントでビルドする場合**は、先に
> `ios/MyttyRemote/Config/Local.xcconfig` を作って Team ID と Bundle ID を
> 自分の値に差し替える必要があります。手順は
> [自分のアカウントでビルドする](docs/building_ja.md#自分のアカウントでビルドする)
> を参照してください。

必要環境、libghostty の準備、test、debug 実行、app bundle 作成、tag による
release は [Mytty のビルド](docs/building_ja.md) を参照してください。

設計と Agent 連携の詳細は [`docs/design.md`](docs/design.md)、
[`docs/agent-integrations.md`](docs/agent-integrations.md)、
[`docs/agent-events.md`](docs/agent-events.md) にあります。

## License

MIT
