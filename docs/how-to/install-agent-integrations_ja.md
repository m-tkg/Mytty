# エージェント連携を導入して確認する

coding agent の provider を hook 連携で有効化し、Settings のトグルを押した
だけで満足せずに実際に動くところまで確認する手順。

## provider を有効にする

**Settings > Agent Integrations** を開き、対象の provider を有効にする。
Mytty がその provider 自身の設定ファイルへ hook を書き込むのは、この
トグルを入れた後だけで、事前に何かが導入されることはない。対応している
provider は Codex、Claude Code、OpenCode、Gemini (Antigravity)、Cursor。

Settings 画面はトグルの状態ではなく、実際の設定ファイルの中身から provider
の状態を判定する。導入済みの hook が Mytty の外で編集されたり一部削除され
たりしていると、黙って導入済み扱いにはならず **Needs repair** と表示され
る。provider を一度オフにして再度オンにすると hook のエントリだけを書き
直せる。そのファイル内の無関係な設定には触れず、Mytty 自身の
`mytty-agent-hook` helper を呼ぶ handler だけを対象にする。

## provider を再起動する

起動済みの provider process は起動後に導入された hook を読み込まないため、
既存の session はそれまで通り動き続ける。

Codex は command hook に明示的な trust 承認が要るため、再起動に加えて確認
の手順が要る。

1. 起動中の Codex CLI を終了し、新しい process を起動する。
2. 新しい process で `/hooks` を実行する。
3. mytty の hook が入っている event を選び、Return を押す。
4. `mytty-agent-hook codex` で終わる command を選ぶ。
5. `Trust` 欄の確認が必要なら Space か Return で承認する。
6. mytty のエントリすべてで `Trust: Trusted` になるまで繰り返す。event
   一覧の `Active` が `Installed` と一致していれば良い。

Claude Code、OpenCode、Antigravity、Cursor は再起動するだけで良く、user
settings や hook、plugin を読み直す。個別の trust 承認は要らない。

## 実際に動くか確認する

provider で新しい session を始め、次を一通り確認する。

1. prompt を投げる。tab がエージェント実行中の表示に切り替わること。
2. Codex、Claude Code、OpenCode では、permission または input のリクエスト
   を発生させる。tab の badge と Attention drawer に該当項目が 1 件出る
   こと。
3. その tab を画面に出したままもう一度リクエストを発生させる。pane が
   既に目の前にあるので macOS 通知は出ないこと。
4. 別の tab に切り替えてから再度リクエストを発生させる。今度は Mytty に
   通知権限があれば macOS 通知が届くこと。
5. Attention drawer のその項目から **Focus Terminal** と **Acknowledge**
   を使い、どちらも正しい pane に作用すること。
6. Settings で provider を無効化し、その設定ファイル内にある無関係な hook
   がそのまま動き続けることを確認する。

Antigravity の hook は lifecycle と結果の状態しか報告せず、承認・入力
のリクエストは作らない。したがって手順 2 は該当しない。Cursor の hook も
承認リクエストを直接は作らないが、mytty は `beforeShellExecution` と
`afterShellExecution` の間隔からシェル承認待ちを推定する
([Agent providers](../reference/agent-providers_ja.md) 参照)。手順 2 で
これを確認するには、Cursor が自動承認しないコマンドを実行し、Cursor
自体の UI では承認せずにおよそ10秒待つ。

## provider ごとの hook 参考資料

- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [OpenCode plugins](https://opencode.ai/docs/plugins/)
- [Antigravity hooks](https://www.antigravity.google/docs/hooks)
- [Antigravity plugins](https://www.antigravity.google/docs/plugins)
- [Cursor hooks](https://cursor.com/docs/hooks)

各 provider の event が内部でどう対応するかは
[Agent providers](../reference/agent-providers_ja.md) を参照。
