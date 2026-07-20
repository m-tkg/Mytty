# iPhone から Mac に接続する

Mytty の iOS リモートアプリを Mac とペアリングする手順、接続後にできること、
Attention のプッシュ通知が iPhone に届く仕組みをまとめる。

## iPhone をペアリングする

Mac 側で **設定 > iOS Remote Access** を開き、**ペアリングコードを生成**を
押す。表示された 6 桁を Mytty の iOS アプリに入力する。Mac は Bonjour で
見つかり、成立した接続はペアリング済みで暗号化される。

Mac はポート 51820 で待ち受け、そのポートが使用中なら自動的に別ポートへ
切り替わる。実際に使われているポートは設定画面で確認できる。Tailscale の
ような VPN 越しで Bonjour が届かない場合は、探索させる代わりにアドレスを
直接入力する。ペアリング試行はキャンセルでき、30 秒で自動的にタイムアウト
する。

一度ペアリングした Mac は、後から iOS アプリの設定画面でラベルや接続方法
(Bonjour サービス名、または手動のホストとポート)を再ペアリングなしで
編集できる。

## iPhone から pane を操作する

<p>
  <img src="../images/ios-pane.png" alt="iPhone に映した Mac の pane とコントロールキーバー" width="280">
</p>

iPhone からは window・tab・pane を辿り、pane を開くとその場でライブ表示
される。pane は Mac 側の terminal と同じ色(bold・dim・反転表示を含む)で
描画され、block cursor も出る。scrollback は最大 10,000 行まで iPhone 側に
反映される。新しい出力への追従は最下部にいる間だけ働くので、読みたい箇所
までスクロールして遡っても、そこから勝手に動くことはない。エージェントや
pager、editor のような全画面型の terminal アプリには元々 scrollback が
無いため、そうした pane 上でのスクロール操作は代わりに mouse-wheel 入力と
して Mac に転送され、アプリ自身のスクロール(エージェントの履歴表示など)
を iPhone から操作できる。

入力はそのまま pane に送られる。日本語は iPhone 自体の IME で変換し
(漢字変換は端末側で行われ、確定した文字だけが送信される)、Ctrl・Option・
矢印など物理キーボードが持つキーはコントロールキーバーから送れる。バーの
貼り付けキーは iPhone のクリップボードをペーストとして pane に送り、pane
ツールバーのコピーボタンはバッファのスナップショットを固定表示する画面を
開いて、iOS 標準の選択操作でテキストを選べる。**Copy All** で全文を一括
コピーすることもできる。

接続が切れると pane にバナーが出て、それまでの内容は薄く表示され、
**Reconnect** をタップするまで入力は無効になる。アプリがフォアグラウンド
に戻ったときは自動で再接続される。どちらの経路でも同じ pane に戻り、その
間に Mac 側でその pane が閉じられていれば pane 一覧へ、tab ごと閉じられて
いれば tab 一覧へ戻る。

ブラウザ pane を開くとタイトルと現在の URL が表示され、Mac 側の遷移に
追従して更新される。同じページを iPhone のアプリ内 Safari で開くボタンと
URL をコピーするボタンも備える。

## Attention をプッシュ通知で受け取る

<p>
  <img src="../images/ios-push.png" alt="発生元の Mac 名が入った Attention のプッシュ通知" width="280">
</p>

ペアリング済みであれば、Attention の項目は Apple Push Notification service
経由でも iPhone に届く。席を外している間にエージェントが承認を求めても、
リモートアプリを終了していれば通知だけで気づける。プッシュが送られるのは
Mytty が最前面でないときで、これには Attention を出した pane が画面上では
まだフォーカスされたままのケースも含む。実行中のエージェントを置いて離席
した状況はまさにこれなので、Mac 側のバナーと二重に届くことはない。

このプッシュを中継するのは Cloudflare Worker(`cloudflare/push-relay`)で、
Mac 側で何かを設定する必要はない。iPhone が Worker に直接登録し、Mac には
その handle だけが渡される。通知本文が平文で中継に届くことはなく、Mac は
ペアリング時に確立した鍵で本文を封をし、iPhone 側の notification service
extension が iOS の表示直前にそれを開く。Cloudflare から実際に見えるのは
デバイストークン、ランダムな Mac 識別子、暗号文だけである。復号できない
プッシュが届いた端末には、内容ではなく Attention の種別だけを示す
プレースホルダーが表示される。

通知をタップすると、それを出した pane までアプリが自動でたどり着く。
対象の Mac、window、tab を順に降りていく形になる。その pane が既に閉じて
いれば、その Mac のセッション画面で止まる。

トグルをオフにすればペアリングを解いたわけではなくプッシュだけ止められる。
自分の Apple Developer team で iOS アプリをビルドしている場合は、この
Worker の自己ホストが任意ではなく必須になる。手順は
[`cloudflare/push-relay/README.md`](../../cloudflare/push-relay/README.md)
を参照。
