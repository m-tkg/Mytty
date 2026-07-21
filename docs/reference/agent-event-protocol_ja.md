# Agent event protocol リファレンス

コーディングエージェントの hook が実行状態を Mytty に報告するためのワイヤープロトコルです。トランスポート、provider ごとのアダプタ、`mytty-agent-hook` helper、provider 別インストーラーはすべて実装済みです。出典は `Sources/MyTTYCore/AgentEvent.swift`、`Sources/MyTTYCore/AgentHookBridge.swift`。どの provider がどの event kind を発行するかは [Agent providers](agent-providers_ja.md) を参照してください。

## 環境変数

Mytty の各ターミナル surface には次の3つの環境変数が渡されます。

```text
MYTTY_EVENT_SOCKET
MYTTY_SURFACE_ID
MYTTY_EVENT_CAPABILITY
```

`MYTTY_EVENT_CAPABILITY` はその surface に限定して event 送信を許可するものです。ターミナル入力、画面キャプチャ、他 surface の event を許可するものではありません。surface が閉じられると Mytty はこれを失効させます。

## トランスポート

`MYTTY_EVENT_SOCKET` に接続します。パーミッション `0600` のユーザー専用 Unix stream socket です。1接続につき UTF-8 の JSON エンベロープを1つ、改行終端で送ります。リクエストの最大サイズは 64 KiB です。日時は ISO 8601 です。

```json
{
  "schemaVersion": 1,
  "capability": "MYTTY_EVENT_CAPABILITY の値",
  "event": {
    "schemaVersion": 1,
    "id": { "rawValue": "B9AA8B83-B42D-4C11-B838-36B84C73032A" },
    "runID": { "rawValue": "74C4B46D-9251-46AD-9200-61C97D98D43D" },
    "sessionID": "0190f6f3-2a50-7000-8000-000000000001",
    "surfaceID": { "rawValue": "MYTTY_SURFACE_ID の値" },
    "provider": "codex",
    "kind": "approval-requested",
    "occurredAt": "2026-07-16T07:00:00Z",
    "message": "Approve the dependency update."
  }
}
```

サーバーは JSON レスポンスを1つ返して接続を閉じます。

```json
{ "ok": true, "inserted": true }
```

同一イベントの冪等なリトライは `inserted: false` を返します。不正な JSON、認可失敗、サイズ超過、内部ストレージ障害は `ok: false` と安定したエラーコードを返します。認可失敗のレスポンスに capability の値がそのまま含まれることはありません。

## エンベロープのフィールド

| フィールド | 型 | 備考 |
| --- | --- | --- |
| `schemaVersion`(外側) | Int | エンベロープのスキーマバージョン、現在は `1` |
| `capability` | String | その surface の `MYTTY_EVENT_CAPABILITY` と一致していること |
| `event.schemaVersion` | Int | event のスキーマバージョン、現在は `1` |
| `event.id` | `{rawValue: UUID}` | hook が同じイベントを再送するときも変わらないこと |
| `event.runID` | `{rawValue: UUID}` | 1回の agent run(1プロンプト/1ターン)の間は変わらない |
| `event.sessionID` | String? | provider 自身のセッション/会話識別子。その provider がフォアグラウンドのエージェントである間だけ表示される |
| `event.surfaceID` | `{rawValue: <MYTTY_SURFACE_ID>}` | そのペインの `MYTTY_SURFACE_ID` と一致していること |
| `event.provider` | String | `codex`、`claude-code`、`opencode`、`antigravity`、`cursor` のいずれか |
| `event.kind` | String | 下記の event kind 一覧を参照 |
| `event.occurredAt` | String | ISO 8601 タイムスタンプ |
| `event.message` | String? | 承認プロンプトの文言など、人間可読の補足情報(任意) |

## Event kind 一覧

`AgentEventKind`(ワイヤー上の値):

| Kind | 意味 |
| --- | --- |
| `started` | 新しいプロンプトまたはターンが始まった |
| `running` | input/approval 待ちのあと処理が再開した |
| `input-requested` | エージェントがユーザーからの自由入力を必要としている |
| `approval-requested` | エージェントが承認/却下の判断を必要としている |
| `succeeded` | run がエラーなく完了した |
| `failed` | run がエラーで終了した |
| `disconnected` | provider プロセスの切断により run が終了した |

reducer は、run が `succeeded`/`failed` などのあと静かになった時点で内部的な `idle` という `AgentRunState` も導出します(これはワイヤー上の event kind ではありません)。`Sources/MyTTYCore/AgentEvent.swift` の `AgentRunState` を参照してください。

## Lifecycle のルール

hook は待ち状態や終了を表すイベントより前に `started` を発行してください。input/approval 待ちのあと処理が再開したら `running` を発行してください。人間が読むターミナル出力をパースしてこれらの event を合成することは禁止です。構造化された hook payload のみを使います。

## 通知パネルの item 生成

Mytty が通知(Attention)パネルの item を作るのは次の場合のみです。

- 承認リクエスト
- 入力リクエスト
- failure
- disconnect
- 5分以上動き続けた成功実行

確認済み、あるいは何らかの形で解決済みの item は、解決から24時間はパネルに残り続けます。

## レスポンスコード

`AgentEventServerResponse` は `ok`、`inserted`(成功時のみ設定)、`error`(失敗時のみ設定される安定したコード文字列)の3フィールドを持ちます。

| レスポンス | 意味 |
| --- | --- |
| `{"ok": true, "inserted": true}` | event を受理し、新規に記録した |
| `{"ok": true, "inserted": false}` | すでに記録済みの event(同じ `event.id`)の冪等なリトライ |
| `{"ok": false, "error": "request-too-large"}` | エンベロープが 64 KiB 上限を超えた |
| `{"ok": false, "error": "unauthorized"}` | `capability` がその surface の `MYTTY_EVENT_CAPABILITY` と一致しなかった |
| `{"ok": false, "error": "invalid-request"}` | エンベロープを期待する JSON 形式としてデコードできなかった |
| `{"ok": false, "error": "internal-error"}` | Mytty 側で event の保存に失敗した |

## 参考

- [Agent providers](agent-providers_ja.md): 設定ファイルの場所、provider ごとの hook と event の対応、status bar / session inspector の情報源をまとめています。
- [mytty-ctl リファレンス](mytty-ctl_ja.md): このプロトコルが生成する `AgentRunState` を読み取る `list`/`wait` の仕様を扱います。
