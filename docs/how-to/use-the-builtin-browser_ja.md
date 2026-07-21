# アプリ内ブラウザを使う

Mytty は terminal と並べてブラウザ pane を開ける。ローカルのドキュメントや
プレビューサーバーを見るのにアプリを出る必要がない。ここでは開き方、pane 内の検索、
terminal からのリンクの扱い方を示す。

## ローカルファイルを開く

Command-O を押して HTML ファイルを選ぶ。navigation、検索、閉じる操作を
備えた新しいブラウザ pane が開き、他の split と同じように terminal pane の
隣に並ぶ。

## フォーカス中の pane を検索する

Control-F はフォーカスしている pane が terminal でもブラウザでも同じ
ショートカットで検索欄を開く。pane の種類ごとに違うキーを覚える必要は
ない。

## terminal からリンクをたどる

terminal pane 内のリンクを Command-click すると小さなメニューが出る。

- **Open in browser** で新しいブラウザ pane で開く
- **Open in new tab**
- **Open in new pane (right)** / **Open in new pane (down)**
- **Copy link**

これは表示文字列と実際の URL が異なるハイパーリンクでも動作する。また、
Claude Code のようにマウスをキャプチャするフルスクリーンアプリの表示中
でも、Command-click はそのアプリに吸収されず Mytty のリンク処理まで届く。
