# Mytty の使い方

English version: [usage.md](usage.md)

Mytty を日常的に使うと何ができるのかを一通り見ていきます。設定項目や挙動の
網羅的な一覧は [機能説明](../README_ja.md#機能説明)にあります。ここでは
最初に触れる部分を扱います。

## 動かすまで

Mytty は **macOS 15 以降・Apple Silicon** が必要です。
[Releases](https://github.com/m-tkg/Mytty/releases) から `Mytty.zip` を
ダウンロードして展開し、`Mytty.app` を `/Applications` に移動してください。
署名と notarize 済みなので Gatekeeper の警告は出ません。ソースからビルドする
場合は [Mytty のビルド](building_ja.md)を参照してください。

起動前の設定は不要です。初回起動でログインシェルのウィンドウが開きます。

## ウィンドウ・タブ・ペイン

![サイドバーに 2 つのタブ、pane が左右に分割された画面](images/panes.png)

タブはタイトルバーの帯ではなくサイドバーに並びます。長いタイトルが読めますし、
数が増えても位置が保たれます。各行にはその tab が持つ pane 数が出ます。行を
ドラッグして並べ替えたり、ウィンドウの外へドラッグして新しいウィンドウにでき
ます。

| やりたいこと | 操作 |
| --- | --- |
| 新しい tab / ウィンドウ | Command-T / Command-N |
| 右 / 下に分割 | Command-D / Command-Shift-D |
| pane 間の移動 | Command-Option-矢印 |
| pane を tab いっぱいに拡大 | Control-Command-Return |
| pane / tab を閉じる | Command-Shift-W / Command-W |
| 閉じたものを開き直す | Command-Shift-T |
| サイドバーを畳む | Command-B |

下端のバーはフォーカス中の pane に追従し、作業ディレクトリと、Git 管理下なら
リポジトリと branch を表示します。

覚えるより探したい場合は **Command-Shift-P** でコマンドパレットが開き、すべての
メニューコマンドを入力で絞り込めます。

終了しても失われません。ウィンドウ・tab・pane・分割比・作業ディレクトリは次回
起動時に復元され、エージェントのセッションも再開可能な形で戻ります。

## エージェントと使う

Mytty は「どの pane のエージェントが」「何を求めているか」を把握します。これは
エージェント自身からの情報です。**設定 > Agents** でプロバイダーを有効にすると
そのプロバイダーの設定に hook が導入され、hook が構造化されたイベントを送りま
す。画面の文字列を解析していないので、要求が別の pane に取り違えられることは
ありません。

Codex、Claude Code、OpenCode、Gemini (Antigravity)、Cursor に対応しています。

![承認リクエストが 1 件並んだ Attention ドロワー](images/attention.png)

エージェントの実行中は、サイドバーの行とステータスバーに状況が出ます。使用中の
モデル、残りコンテキスト、セッションのコスト、プロバイダーが公開していれば
クォータのメーターも表示されます。

エージェントが応答を求めると **Attention Inbox**(Command-Shift-A)に入ります。
承認リクエスト、質問、失敗、長時間処理の完了です。各項目には発生元の pane が
書かれ、矢印ボタンでその pane へ直接移動できます。対応するまで残るので、別の
tab にいる間に来た要求も戻れば待っています。

Mac の他のアプリを使っている間は macOS の通知が同じ役割を果たします。その pane
が既に目の前にある場合、Mytty は通知しません。

エージェントの作業はスクリーンセーバーの待ち時間より長くなりがちです。
**設定 > General** で、エージェントの実行中、またはエージェントを開いている間は
スリープを抑止できます。同梱のヘルパー(システム設定での一度きりの承認が必要)
により、モニタを閉じた状態にも対応します。

### エージェントに Mytty を操作させる

`mytty-ctl` は、どの pane からでも設定なしに使える CLI です。エージェントが
pane を開いたり分割したり、入力を送ったり、画面を読んだり、別 pane の
エージェントが idle になるか応答待ちになるのを待ったりできます。狙いは、
サブエージェントのチームを「見えないもの」ではなく、**目に見えて割り込める
実際の pane** にすることです。[mytty-ctl](mytty-ctl.md) を参照してください。

## iPhone から Mac に触る

**設定 > iOS Remote Access** を有効にし、**ペアリングコードを生成**して、6 桁を
Mytty iOS アプリに入力します。Mac は Bonjour で見つかり、通信はペアリングされて
暗号化されます。Tailscale などの VPN 越しならアドレスを直接入力もできます。

iPhone からはウィンドウ・tab・pane をたどり、pane を Mac と同じ色のまま実時間で
表示し、入力できます。日本語は iPhone 側の IME で変換してから送られ、Ctrl・
Option・矢印などはキーバーから送れます。

<p>
  <img src="images/ios-pane.png" alt="iPhone に映した Mac の pane とコントロールキーバー" width="280">
  <img src="images/ios-push.png" alt="発生元の Mac 名が入った Attention のプッシュ通知" width="280">
</p>

Attention はプッシュ通知としても届くので、リモートアプリを終了していてもポケット
の中の iPhone がエージェントの停滞を知らせます。通知をタップするとその pane が
開きます。通知本文は Mac 側でペアリング鍵により暗号化され iPhone 側で復号される
ため、中継はエージェントの発言を見ることができません。

## この先

- [機能説明](../README_ja.md#機能説明) — 設定と挙動の網羅的な一覧
- [mytty-ctl](mytty-ctl.md) — エージェントから Mytty を操作する
- [エージェント連携](agent-integrations.md) — 各プロバイダーが報告する内容
- [Mytty のビルド](building_ja.md) — ビルド・テスト・リリース
