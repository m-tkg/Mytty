# iOS リモート app をビルドする

companion の iOS app は `ios/MyttyRemote` にあり、Mac app とは別経路、
`scripts/release.sh` ではなく Xcode Cloud で公開される。ここではローカルで
のビルド方法と、自分の Apple Developer account でビルドする手順を扱う。

## Simulator 向けにビルドする

```sh
make ios
```

XcodeGen で Xcode project を再生成し、iOS Simulator 向けに build する。
実機向けには `make ios-device` を使うが、その前に署名の設定が要る(後述)。

`ios/MyttyRemote` 配下の Swift ファイルを追加・削除したときは、必ず
`make ios` を再実行して、再生成された `project.pbxproj` をそのファイルと
一緒に commit すること。Xcode Cloud は checked-in の project を build する
だけで XcodeGen 自体は実行しないため、再生成を忘れるとローカルでは build
できてもそちらでは "Cannot find … in scope" で失敗する。

## 必要な identifier

このアプリは Attention のプッシュを iOS が表示する前に復号する notification
service extension を同梱しているため、Apple Developer portal に App ID が
1つではなく2つ必要になる。

| Identifier | Capability |
| --- | --- |
| `$(MYTTY_BUNDLE_ID)` | Push Notifications |
| `$(MYTTY_BUNDLE_ID).NotificationService` | なし |

extension 自体には capability が要らない。通知を受け取るだけの役割で、
pairing secret を読むための `keychain-access-groups` entitlement も、App
Groups と違ってその entitlement だけで満たせる。

Xcode Cloud は identifier を自動で作らない。署名の管理はするが、まだ存在
しない App ID を代わりに登録してはくれないため、ローカルでは build が通り
(automatic signing がその場で作ってくれることがある)、Xcode Cloud だけ
失敗するということが起きる。症状としては archive 自体は成功するのに、
`xcodebuild -exportArchive` がすべての distribution method で一斉に code
70 を返す、という形で現れる。登録済みの identifier がないと、export の際
に同梱の extension を署名できない。

## 自分のアカウントでビルドする

署名の既定値(`DEVELOPMENT_TEAM` と `MYTTY_BUNDLE_ID`)は
`ios/MyttyRemote/Config/Signing.xcconfig` にある。このファイルは直接編集
せず、`Config/Local.xcconfig` を作って上書きする。

```sh
cd ios/MyttyRemote
cp Config/Local.xcconfig.sample Config/Local.xcconfig
```

続けて `Config/Local.xcconfig` を編集し、`DEVELOPMENT_TEAM` と
`MYTTY_BUNDLE_ID` を自分の値に書き換える。`Config/Local.xcconfig` は
.gitignore 済みで XcodeGen も読まないため、追跡ファイルに差分は出ない。

上書きするのは `PRODUCT_BUNDLE_IDENTIFIER` ではなく `MYTTY_BUNDLE_ID` で
ある。notification service extension は自分の identifier を
`MYTTY_BUNDLE_ID` から導出しているため、`PRODUCT_BUNDLE_IDENTIFIER` を直接
設定すると app の bundle ID だけが変わり、extension は元の team に登録
された identifier のままになって、自分の team では署名できなくなる。

bundle ID は必ず team とセットで変更すること。既定の bundle ID は元の team
に登録済みで、他のアカウントではプロビジョニングできない。無料の Personal
Team では、特に Push Notifications のような capability をプロビジョニング
できない場合もある。
