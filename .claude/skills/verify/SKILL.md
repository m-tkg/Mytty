---
name: verify
description: Mytty (macOS AppKit/SwiftUI terminal app) をビルド・起動して GUI 動作を実機検証する手順。
---

# Mytty の実機検証

## ビルドと起動

```bash
swift build
nohup .build/debug/Mytty > /tmp/mytty-dev.log 2>&1 &   # pid を控える
```

- 開発ビルド(非 .app)は `ApplicationPathProfile.development` になり、
  設定と状態は `~/.config/mytty-dev` / `~/Library/Application Support/mytty-dev`
  に分離される。ユーザーの本番 Mytty(release プロファイル)とは干渉しない。
- 前回の dev セッションのウィンドウが復元される(全ウィンドウが同座標に
  重なって出ることが多い)。

## GUI 操作の自動化

- `screencapture -x out.png` は許可済みで動く。`sips -c H W --cropOffset Y X`
  で切り出すとトークン節約になる。
- CGEvent の合成(クリック・ドラッグ・キー送信)も許可済み。
  スクラッチパッドに `driver.swift` を作って `swiftc -O -o driver driver.swift`
  でビルドする(過去セッションの例: `windows <pid>` で CGWindowList の
  ウィンドウ座標一覧、`drag x1 y1 x2 y2 [ms]`、`path x1 y1 x2 y2 x3 y3`
  (経由点付きドラッグ)、`key <pid> <keycode> cmd`、`activate <pid>`)。
- 座標系: CGWindowList と CGEvent は左上原点のポイント座標で一致する。
  AppKit(`draggingSession(endedAt:)` など)は左下原点なので変換に注意。
  画面は 1512x982pt(2x Retina)。
- キーコード: T=17, N=45, W=13。`postToPid` でアプリが背面でも届く。

## 検証のコツ

- ウィンドウ増減は `driver windows <pid>` の行数で判定できる。
- タブ行はサイドバー上端からタイトルバー+ヘッダー約 102pt 下が 1 行目、
  行ストライドは縦置きで 53pt。
- タブのタイトルが全部同じ("masaki" など)場合、並べ替えの検証は
  選択ハイライトの位置変化で判定する。
- 終了は `kill <pid>`。終了時にセッションが保存される。
