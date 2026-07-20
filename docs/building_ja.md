# Mytty のビルド

> **iOS リモート app を自分のアカウントでビルドする場合**は、先に
> `ios/MyttyRemote/Config/Local.xcconfig` を作って Team ID と Bundle ID を
> 自分の値に差し替える必要があります。手順は
> [自分のアカウントでビルドする](#自分のアカウントでビルドする) を参照。
> 作らずに実機ビルドすると署名エラーだけが出て原因に気づけません。

## 必要環境

- macOS 15 以降を搭載した Apple Silicon Mac
- Swift 6.2 に対応する Xcode toolchain
- Git
- 固定した Ghostty submodule が要求する Zig。現在の script は Homebrew の
  `zig@0.15` を探し、厳密な version を確認します。

必要な場合は Zig を導入します。

```sh
brew install zig@0.15
```

## libghostty の準備

clone 時に submodule を含めるか、clone 後に初期化します。

```sh
git submodule update --init --recursive
scripts/build-ghostty.sh
```

script は native arm64 の `GhosttyKit.xcframework`、Ghostty theme、shell
integration、app bundle に必要な terminfo を生成します。固定 toolchain と現在の
SIMD compatibility switch は [`ghostty-build.md`](ghostty-build.md) を参照して
ください。

Ghostty の revision を変えた場合は再実行します。Swift の build ごとに実行する
必要はありません。

## Build と test

```sh
swift build
swift test
Tests/ReleasePackagingTests.sh
```

開発中は次の command で実行できます。

```sh
swift run Mytty
```

debug 実行は **Mytty Dev** として表示され、Dock に `DEV` badge を付け、次の
場所を使用します。

- `~/.config/mytty-dev/`
- `~/Library/Application Support/mytty-dev/`
- `~/Library/Logs/mytty-dev/`
- 一時 directory 内の `com.m-tkg.mytty.dev/` socket

導入済み release の設定や session には影響しません。対応 provider は user
global な設定を使うため Agent hook の導入だけは共有しますが、各 terminal pane
は個別の event socket を渡します。

## App bundle の作成

ローカル debug bundle を作成します。

```sh
scripts/bundle.sh debug
open "dist/Mytty Dev.app"
```

arm64 release bundle を作成します。

```sh
VERSION=0.1.0 BUILD_NUMBER=1 scripts/bundle.sh release
open dist/Mytty.app
```

`SIGN_IDENTITY` または署名 identity の検出処理から適切な Developer ID が得られる
場合は、それを使用します。それ以外はローカルテスト向けの ad-hoc 署名を付けます。
公開 artifact は release workflow で署名・notarize する必要があります。

## Release 手順

`v*` tag を push すると [release workflow](../.github/workflows/release.yml) が
開始します。Swift と packaging の test、Apple Silicon app の build、署名、
notarize、ticket の staple を行い、`Mytty.zip` を GitHub Releases に公開します。
repository に署名または notarize 用 secret がなければ、workflow は意図的に失敗
します。

例:

```sh
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

`make release VERSION=x.y.z`(`scripts/release.sh`)はこれをまとめて行う
helper で、ローカルで test suite を実行してから `main` と annotated tag を
push する。`x.y.z-beta.1` や `x.y.z-rc.2` のように pre-release suffix を
付けた VERSION を指定すると、stable release ではなく GitHub の pre-release
として tag・公開される — workflow が tag の suffix を検出して
`gh release create` に `--prerelease` を渡す。受け付ける suffix の形式は
`ApplicationVersion`(`Sources/MyTTYApp/ApplicationUpdate.swift`)がパース
できる形式と一致しているため、この script が受け付ける tag は必ずアプリ内
updater でも解決できる。

## iOS リモート app

companion iOS app は `ios/MyttyRemote` にあり、Mac の release 手順には含まれ
ません。`make ios` は XcodeGen で Xcode project を再生成して iOS Simulator
向けに build し、`make ios-device` は実機向けに build します（署名が必要）。

### 自分のアカウントでビルドする

署名の既定値（`DEVELOPMENT_TEAM` / `PRODUCT_BUNDLE_IDENTIFIER`）は
`ios/MyttyRemote/Config/Signing.xcconfig` にあります。このファイルは編集せず、
`Config/Local.xcconfig` を作って上書きしてください。

```sh
cd ios/MyttyRemote
cp Config/Local.xcconfig.sample Config/Local.xcconfig
# DEVELOPMENT_TEAM と PRODUCT_BUNDLE_IDENTIFIER を自分の値に書き換える
```

`Config/Local.xcconfig` は .gitignore 済みで XcodeGen も読まないため、追跡
ファイルに差分は出ません。Bundle ID は必ず Team とセットで変更してください。
既定の Bundle ID は元の Team に登録済みで、他アカウントではプロビジョニング
できません。無料の Personal Team では一部 capability をプロビジョニングでき
ない場合があります。
