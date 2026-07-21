[English](README.md)

# Mytty について

Mytty は AI Agent を使うときに便利な機能を詰め込んだターミナルエミュレータです。

発音は "マイティー" です

## 便利なところ
- ステータスバーで AI Agent の利用状況がわかる
- ステータスバーからプロジェクトのフォルダや GitHub へ移動できる
- web へのアクセスを pane の中で実行できる
- AI Agent 実行中のスリープ防止
- iOS デバイスとの連携
- 操作の GIF 録画機能
- 入力キーの toast 表示(録画時に便利)
- 再起動時、AI Agent のセッションを復元できる
- 再起動時だけでなく、ペインやタブを閉じたときにも履歴から復元できる

## チュートリアル

- [Mytty を使い始める](tutorials/getting-started_ja.md)

## もっと進んだ使い方

- [mytty-ctl でエージェントのチームを動かす](how-to/orchestrate-agents-with-mytty-ctl_ja.md)
- [iPhone から Mac に接続する](how-to/connect-from-iphone_ja.md)
- [アプリ内ブラウザを使う](how-to/use-the-builtin-browser_ja.md)
- [pane を GIF として録画する](how-to/record-a-gif_ja.md)

## リファレンス

- [mytty-ctl リファレンス](reference/mytty-ctl_ja.md)
- [Agent providers リファレンス](reference/agent-providers_ja.md)
- [Agent event protocol リファレンス](reference/agent-event-protocol_ja.md)

## 説明

- [アーキテクチャ](explanation/architecture_ja.md)
- [mytty-ctl のアーキテクチャ](explanation/mytty-ctl-architecture_ja.md)
- [オートコンプリートの設計](explanation/autocomplete-design_ja.md)

## その他

- [macOS アプリをソースからビルドする](how-to/build-macos-app_ja.md)
- [リリースする](how-to/release-a-version_ja.md)
- [iOS リモートアプリをビルドする](how-to/build-ios-remote-app_ja.md)
- [`cloudflare/push-relay/README.md`](../cloudflare/push-relay/README.md) はプッシュ通知中継の自己ホスト手順(英語)。
- [`.claude/skills/mytty-panes/SKILL.md`](../.claude/skills/mytty-panes/SKILL.md) には `mytty-ctl` を使ったタスクレシピがあります。
