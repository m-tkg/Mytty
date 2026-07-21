# macOS アプリをソースからビルドする

## 必要なもの

- Apple Silicon の Mac(macOS 15 以降)
- Swift 6.2 を含む Xcode toolchain
- Homebrew の `zig@0.15`

Zig のバージョンは固定した Ghostty submodule が要求するもので、`scripts/build-ghostty.sh` がビルド前に確認します。入っていなければ入れておきます。

```sh
brew install zig@0.15
```

## libghostty をビルドする

submodule を取得して、Ghostty をビルドします。

```sh
git submodule update --init --recursive
scripts/build-ghostty.sh
```

`GhosttyKit.xcframework` に加えて、アプリバンドルが必要とする Ghostty のテーマ、shell integration、terminfo が生成されます。毎回のビルドで実行する必要はなく、Ghostty のリビジョンを変えたときだけやり直します。

## ビルドしてテストする

```sh
swift build
swift test
Tests/ReleasePackagingTests.sh
```

開発中は `swift run Mytty` で起動します。デバッグビルドは **Mytty Dev** という名前で、Dock アイコンに `DEV` バッジが付き、状態を別の場所に保存します。

| 用途 | パス |
| --- | --- |
| 設定 | `~/.config/mytty-dev/` |
| アプリケーションデータ | `~/Library/Application Support/mytty-dev/` |
| ログ | `~/Library/Logs/mytty-dev/` |

ソケットも一時ディレクトリ内に分けて作るので、インストール済みのリリース版とは干渉しません。ただしエージェントのフック導入だけは共有されます。各プロバイダのフックはユーザー全体の設定ファイルに書かれるためです。

## アプリバンドルを作る

デバッグビルドをバンドルする場合。

```sh
scripts/bundle.sh debug
open "dist/Mytty Dev.app"
```

リリースビルドをバンドルする場合。

```sh
VERSION=0.1.0 BUILD_NUMBER=1 scripts/bundle.sh release
open dist/Mytty.app
```

`SIGN_IDENTITY` または `scripts/resolve-signing-identity.sh` から Developer ID が見つかればそれで署名し、見つからなければ ad-hoc 署名になります。ad-hoc 署名は手元での確認には使えますが、他の Mac には配布できません。配布する成果物はリリースワークフローの署名と notarize を通します。手順は [バージョンをリリースする](release-a-version_ja.md) を参照してください。

## Xcode 27 beta で SIMD のビルドが失敗する

固定した Ghostty のリビジョンは Zig 0.15.2 を必要としますが、同梱の libc++ が Xcode 27 beta の SDK に対して Ghostty の SIMD の C++ ソースをコンパイルできません。この SDK が、コンパイル時に期待される `INFINITY` マクロを公開しなくなったためです。

`scripts/build-ghostty.sh` は既定で SIMD を無効にして回避しています。影響するのは vendor ライブラリのビルドだけで、Mytty 本体には及びません。固定 toolchain がこの beta SDK 世代を過ぎたら、`MYTTY_GHOSTTY_SIMD=true` を付けてスクリプトを実行し、本来の SIMD 経路でビルドできることを確認してください。
