---
name: mytty-panes
description: Mytty の複数ペインを mytty-ctl で操作し、他のペインで動くサブエージェント(Claude/Codex/Cursor など)をチームとして働かせる。「ペインを分割して並行作業させて」「別のAIにレビューさせて」のような依頼で使う。
---

# mytty-panes: Mytty ペインでサブエージェントチームを動かす

このスキルは、今動いている自分自身(このペインの AI)が「司令塔」となり、
`mytty-ctl` で他のペインを開いて別のエージェントを起動し、完了を待って結果を
回収するための手順をまとめたもの。詳しいプロトコル・アーキテクチャは
`docs/reference/mytty-ctl.md` を参照。

## 前提

`mytty-ctl` は追加設定なしでこのペインから使える。以下の環境変数が既に
セットされている:

```bash
echo "$MYTTY_CTL_BIN"       # mytty-ctl バイナリの絶対パス
echo "$MYTTY_SURFACE_ID"    # このペイン自身の pane ID
```

以降の例では `mytty-ctl` を `PATH` 経由と仮定して書くが、実際には
`"$MYTTY_CTL_BIN"` を使うほうが確実。

## 基本の手順

1. **ペインを確保する**: `mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd <作業ディレクトリ>`。
   サブエージェント同士がファイルを取り合わないよう、可能なら `git worktree`
   ごとに別ディレクトリを渡す。JSON レスポンスの `paneID` を控える。
2. **エージェントを起動する**: `mytty-ctl send <paneID> "claude" --enter`
   (または `codex` / `cursor-agent` など)。
3. **指示を投げる**: `mytty-ctl send <paneID> "<プロンプト>" --enter`。
4. **完了を待つ**: `mytty-ctl wait <paneID> --until idle`。複数ペインを
   並行させる場合は、この `wait` を Bash ツールの `run_in_background: true`
   で pane 数ぶん同時に投げ、完了通知が来るたびに次のステップへ進む。
5. **結果を回収する**: `mytty-ctl read <paneID>` で画面テキストを取得し、
   要約・統合してユーザーに報告する。
6. **後片付け**: 用が済んだら `mytty-ctl close-pane <paneID>`。継続対話が
   必要なら閉じずに残す。

## レシピ

### タスクを水平分割して並列実行(単一プロバイダー)

独立性が高く判断基準が同じタスクを、同じプロバイダーの複数インスタンスに
分担させる。

```bash
pane_a=$(mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd worktrees/a | jq -r .paneID)
pane_b=$(mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd worktrees/b | jq -r .paneID)
mytty-ctl send "$pane_a" "claude" --enter
mytty-ctl send "$pane_a" "<タスクAの指示>" --enter
mytty-ctl send "$pane_b" "claude" --enter
mytty-ctl send "$pane_b" "<タスクBの指示>" --enter
# それぞれ `mytty-ctl wait <pane> --until idle` を並列で待ち、
# 終わったものから `mytty-ctl read <pane>` で回収する
```

### 役割分担(調査は Claude、実装は Codex、司令塔は今のAI)

フェーズが直列で、フェーズごとに必要な強みが違うとき。前フェーズの結果を
要約して次のプロンプトに埋め込むのが司令塔の仕事。

```bash
pane=$(mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd . | jq -r .paneID)
mytty-ctl send "$pane" "claude" --enter
mytty-ctl send "$pane" "<調査タスク>" --enter
mytty-ctl wait "$pane" --until idle
survey=$(mytty-ctl read "$pane" | jq -r .content.text)
mytty-ctl close-pane "$pane"

pane=$(mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd . | jq -r .paneID)
mytty-ctl send "$pane" "codex" --enter
mytty-ctl send "$pane" "次の調査結果を踏まえて実装して: $survey" --enter
mytty-ctl wait "$pane" --until idle
mytty-ctl read "$pane"
```

### 実装 + 独立レビュー(セカンドオピニオン)

自己レビューのバイアスを別プロバイダーの視点で相殺する。

```bash
diff=$(mytty-ctl send "$impl_pane" "git diff" --enter; mytty-ctl read "$impl_pane" | jq -r .content.text)
review_pane=$(mytty-ctl split "$MYTTY_SURFACE_ID" right --cwd . | jq -r .paneID)
mytty-ctl send "$review_pane" "claude" --enter
mytty-ctl send "$review_pane" "次のdiffをレビューして: $diff" --enter
mytty-ctl wait "$review_pane" --until idle
mytty-ctl read "$review_pane"
# 指摘があれば mytty-ctl send "$impl_pane" "<指摘>を直して" --enter
```

### 承認待ちのエスカレーション

破壊的操作の承認待ちを検知してユーザーに確認する。Cursor/Antigravity は
`attention` イベントを出さないため非対応(`idle` wait のみ)。

```bash
mytty-ctl wait "$pane" --until attention --timeout-seconds 600
mytty-ctl read "$pane"   # 何を聞かれているか確認してからユーザーに転送する
```

## 注意点

- `wait` はエージェントの hook イベント(`AgentRunState`)を見ている。対象
  プロバイダーの統合が Settings で有効化されていないと、イベントが来ず
  タイムアウトするまでブロックする。初めて使うプロバイダーでは事前に確認する。
- `close-pane` は確認なしで即座に閉じる。人間に結果を見せたいペインは
  閉じずに `mytty-ctl focus <paneID>` でフォーカスを移すとよい。
- サブエージェントがさらにサブエージェントを生む(孫エージェント)のは
  意図した範囲でのみ許可する。無制限に階層化すると収拾がつかなくなる。
