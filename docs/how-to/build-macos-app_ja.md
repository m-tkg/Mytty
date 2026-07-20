# macOS アプリをソースからビルドする

Mytty をローカルでビルドする手順。libghostty の取得、debug バイナリの実行、
application bundle の作成までを扱う。

## 必要環境

- macOS 15 以降を搭載した Apple Silicon Mac
- Swift 6.2 に対応する Xcode toolchain
- Git
- Homebrew の `zig@0.15`。固定した Ghostty submodule がこの厳密な version を
  要求し、`scripts/build-ghostty.sh` がビルド前に確認する

Zig が入っていなければ導入する。

```sh
brew install zig@0.15
```

## libghostty を取得してビルドする

clone 時に submodule を含めるか、clone 後に初期化する。

```sh
git submodule update --init --recursive
scripts/build-ghostty.sh
```

この script は native arm64 の `GhosttyKit.xcframework` に加えて、application
bundle が必要とする Ghostty の theme、shell integration、terminfo を生成する。
再実行が必要なのは Ghostty の revision を変えたときだけで、Swift の build の
たびに実行する必要はない。

## Build と test

```sh
swift build
swift test
Tests/ReleasePackagingTests.sh
```

開発中は `swift run Mytty` で実行する。この debug build は **Mytty Dev** と
して表示され、Dock に `DEV` badge が付き、次の場所に状態を分けて保存する。

- `~/.config/mytty-dev/`
- `~/Library/Application Support/mytty-dev/`
- `~/Library/Logs/mytty-dev/`、および一時 directory 内の別 socket

導入済みの release build にはこの状態が影響しない。対応 provider は user
global な設定から hook を読むため、Agent hook の導入自体は dev と release で
共有される。

## Application bundle を作成する

ローカル debug bundle を作る。

```sh
scripts/bundle.sh debug
open "dist/Mytty Dev.app"
```

arm64 の release bundle を作る。

```sh
VERSION=0.1.0 BUILD_NUMBER=1 scripts/bundle.sh release
open dist/Mytty.app
```

`scripts/bundle.sh` は `SIGN_IDENTITY` または署名 identity の検出処理から
Developer ID が得られる場合はそれで署名する。得られない場合は ad-hoc 署名に
なり、ローカルでの動作確認には十分だが他の Mac に配布するものには使えない。
公開する artifact は release workflow の署名・notarize を通す必要がある。
手順は [バージョンをリリースする](release-a-version_ja.md) を参照。

## トラブルシューティング: Xcode 27 beta での SIMD ビルド失敗

固定した Ghostty の revision は Zig 0.15.2 を必要とするが、その libc++ は
Xcode 27 beta の SDK に対して Ghostty の SIMD C++ ソースをコンパイルできない。
この経路で SDK が期待する `INFINITY` マクロを提供しなくなったためだ。
`scripts/build-ghostty.sh` は既定で SIMD を無効化することでこれを回避して
おり、影響は vendor library の build に限られ、Mytty 本体には及ばない。固定
toolchain がこの beta SDK 世代を過ぎたら、`MYTTY_GHOSTTY_SIMD=true` を設定
して script を実行し、本来の SIMD 経路が build できることを確認する。
