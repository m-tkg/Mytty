# 初めてのエージェントセッション

English version: [first-agent-session.md](first-agent-session.md)

このチュートリアルでは、provider を 1 つ有効にして pane 上でコーディング
エージェントを動かし、そのエージェントからの要求が Attention Inbox に届く
ところまでを確認します。tab と pane の基本操作は前提にしているので、まだの
場合は先に [Mytty を使い始める](getting-started_ja.md)を済ませてください。

## provider を有効にする

**設定 > Agents** を開き、provider を 1 つ有効にします。Mytty は Codex、
Claude Code、OpenCode、Gemini (Antigravity)、Cursor に対応しているので、
すでにインストールしてログイン済みのものを選んでください。有効化すると、
その provider 自身の設定ファイルに hook が追加されます。変更はその
ツールの設定内に閉じており、そこで他に設定してある内容には触れません。

先に理解しておくと分かりやすい点があります。Mytty は画面の文字を読んで
Agent の状況を推測することはしません。いま入れた hook によって、Agent 自身が
構造化されたイベントを送るようになるので、この先出てくる通知はどれも発生元の
pane が明確に紐づいています。

## エージェントを起動して何かやらせる

pane を開き、有効にした provider の CLI を起動します。Claude Code なら
`claude`、Codex なら `codex` です。起動できたら、数秒以上かかる作業、
できれば途中で承認が必要になるような作業を頼んでみてください。ファイルの
編集や shell コマンドの実行あたりが分かりやすいです。作業が進む間、その
pane のサイドバー行とステータスバーを見ておきます。使用中のモデル、残り
コンテキスト、推定セッションコストが、Agent からの報告に合わせてすぐに
反映されます。回転アイコンは Agent が実際にターンを処理している間だけ表示
され、prompt で入力を待っている間は出ません。

## Attention Inbox に届くのを見る

Agent が承認を求めたり、作業を終えたり、失敗したりすると、そのイベントが
Attention Inbox に入ります。Command-Shift-A で開いてみます。

![承認リクエストが 1 件並んだ Attention ドロワー](../images/attention.png)

各項目には発生元の pane が書かれ、項目の矢印ボタンでその pane へ直接移動
できます。Agent が次の質問をする前に別の tab に切り替えてみてください。
後で Inbox を確認したとき、その項目はまだそこにあるはずです。対応するか、
発生元の pane に自分でフォーカスするまで残り続けるからです。逆に、イベントが
届いた時点ですでにその pane を見ていた場合は、そもそも未読として扱われません。

Mac の他の作業をしている間は、代わりに macOS の通知が同じ役割を果たします。
すでにその pane が目の前にある場合 Mytty は通知を出さないので、たった今
見ていたことについて重ねて通知されることはありません。

## 作業中に Mac を眠らせない

Agent の作業はスクリーンセーバーが働き始める時間より長くなりがちです。
**設定 > General** に、Agent が実行中の間だけ、あるいは pane で Agent の
CLI が開いている間はずっとスリープを止める設定があります。蓋を閉じた状態にも
同梱ヘルパー(システム設定での一度きりの承認が必要)で対応できます。Agent を
放置して動かすつもりなら、ここでオンにしておくとよいです。

## もう一歩先: エージェントに Mytty を操作させる

ここまでは Agent の様子を外から眺めているだけでした。`mytty-ctl` は、どの
pane からでも設定なしに使える CLI で、Agent がこれを使って pane を開いたり
分割したり、入力を送ったり、画面を読んだり、別 pane の Agent が idle になる
か応答待ちになるのを待ったりできます。いま Agent が動いている pane の中から
試してみてください。

```sh
"$MYTTY_CTL_BIN" split "$MYTTY_SURFACE_ID" right --cwd "$PWD"
```

これで、今の pane と同じ作業ディレクトリのまま右側に新しい pane が開きます。
そこでテストを走らせたり、別の Agent を並べて動かしたりできます。
`mytty-ctl` の狙いは、サブエージェントのチームを「見えないもの」ではなく、
目に見えて割り込める実際の pane にすることです。別 pane の Agent 状態を
待つところまで含めたコマンド全体は、
[mytty-ctl でエージェントのチームを動かす](../how-to/orchestrate-agents-with-mytty-ctl_ja.md)
にまとめてあります。

## この先

- [mytty-ctl でエージェントのチームを動かす](../how-to/orchestrate-agents-with-mytty-ctl_ja.md)
  では、別の Agent から pane を操作する流れを詳しく扱います。
- [Agent providers](../reference/agent-providers_ja.md)には、各 provider が実際に
  何を報告し、Mytty がそこからどう状態を組み立てているかが書かれています。
