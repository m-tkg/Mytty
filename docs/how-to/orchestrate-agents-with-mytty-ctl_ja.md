# mytty-ctl でエージェントのチームを動かす

同梱されている CLI `mytty-ctl` を使うことで、 AI エージェントが他のペインを開いて操作することができます。`Task`/`Agent` ツールが作るような見えないサブエージェントではなく、画面に見えて割り込めるペインでサブエージェントの小さなチームを動かすイメージです。

Mytty ではmすべてのペインのシェル環境に `MYTTY_CONTROL_SOCKET`、`MYTTY_CTL_BIN`、`MYTTY_SURFACE_ID` が自動で入るため、エージェントは他に準備することなく `"$MYTTY_CTL_BIN" agent spawn --provider codex --task "..."` のように他の AI Agent を呼び出すことができます。

mytty-ctl で使える全コマンドの一覧と JSON 出力の形式は [mytty-ctl リファレンス](../reference/mytty-ctl_ja.md) にまとめてあります。

## 使い方

Mytty オーケストレーションの使い方は2つあります。

### プロンプトに、 CLI の実行を記述する

下記のように、プロンプトで先にコマンドを実行させてから具体的なタスクの指示を出すパターンです。

> まず `mytty-ctl guide` を実行してから、ペインを分割してこの diff を Claude Code に並行でレビューさせて。

この場合、 CLI のインストールさえできていれば仕様中の CLAUDE.md や AGENTS.md を変更する必要はありません。

### あらかじめ CLAUDE.md や AGENTS.md に使い方を書いておく

CLAUDE.md や AGENTS.md に使い方を書いておくことで、 「まず `mytty-ctl guide` を実行してから」というのを毎回書かなくてもよくなり、下記のプロンプトで実行できるようになります。

> ペインを分割して、この diff を Claude Code に並行でレビューさせて。

## 設定画面

この機能に関わる設定は 設定 > オーケストレーション に集約されています。

**CLI に PATH を通す**
「CLI をインストール」で `~/.local/bin` にシンボリックリンクを作成します。

**エージェントに使い方を教える**
「Agent に Mytty オーケストレーションの使い方を教える」をオンにすると、`~/.claude/skills/mytty-panes/SKILL.md` と `~/.codex/AGENTS.md` に `mytty-ctl` の使い方を記述します。

「書き込む内容を表示」を開くと実際に書き込まれる文面をそのまま確認できます。これを開くだけでは書き込まれません。

同じ画面の下部に、呼び出し方の例が並んでいるので参考にしてください。
