# iOS 用の MyttyRemote をビルドする

## Simulator 向けにビルドする

```sh
make ios
```

XcodeGen で Xcode project を再生成し、iOS Simulator 向けにビルドします。
実機向けには `make ios-device` を使いますが、その前に署名の設定が必要です(後述)。

## 必要な identifier

このアプリは通知のプッシュを iOS が表示する前に復号する notification service extension を同梱しているため、Apple Developer portal に App ID が1つではなく2つ必要になります。

| Identifier | Capability |
| --- | --- |
| `$(MYTTY_BUNDLE_ID)` | Push Notifications |
| `$(MYTTY_BUNDLE_ID).NotificationService` | なし |

extension 自体には capability が不要です。通知を受け取るだけの役割で、 pairing secret を読むための `keychain-access-groups` entitlement も、App Groups と違ってその entitlement だけで満たせます。

## developer team の変更

署名の既定値(`DEVELOPMENT_TEAM` と `MYTTY_BUNDLE_ID`)は
`ios/MyttyRemote/Config/Signing.xcconfig` にあります。このファイルは直接編集せず、`Config/Local.xcconfig` を作って上書きします。

```sh
cd ios/MyttyRemote
cp Config/Local.xcconfig.sample Config/Local.xcconfig
```

続けて `Config/Local.xcconfig` を編集し、`DEVELOPMENT_TEAM` と `MYTTY_BUNDLE_ID` を自分の値に書き換えます。上書きするのは `PRODUCT_BUNDLE_IDENTIFIER` ではなく `MYTTY_BUNDLE_ID` です。
