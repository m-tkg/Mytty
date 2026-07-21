# バージョンをリリースする

Mytty は tag 契機の GitHub Actions workflow でリリースされます。クリーンな `main` から release(pre-release を含む)を切る手順を示します。

## release script を実行する

```sh
make release VERSION=x.y.z
```

これは `scripts/release.sh` をまとめた helper で、ローカルで test suite を実行してから `main` と annotated tag を push します。作業 tree はクリーンな状態で実行してください。script は push する内容とローカルの変更を突き合わせてくれるわけではありません。

pre-release suffix を付けた VERSION を指定すると、stable release ではなく GitHub の pre-release として公開されます。

```sh
make release VERSION=x.y.z-beta.1
```

workflow が tag の suffix を検出し、`gh release create` に `--prerelease` を渡します。受け付けるのは `ApplicationVersion` (`Sources/MyTTYApp/ApplicationUpdate.swift`) がパースできる suffix 形式だけなので、`scripts/release.sh` を通った tag はアプリ内 updater でも後で解決できます。アプリ内 updater が pre-release を候補に出すのは、ユーザーが **Check for Updates** を Option クリックした場合だけで、通常のチェックや起動時・About 画面での自動チェックは stable release にとどまります。

## workflow が行うこと

`v*` tag を push すると [release workflow](../../.github/workflows/release.yml) が始まり、次を行います。

1. `swift test` と `Tests/ReleasePackagingTests.sh` を実行します
2. Apple Silicon app を build します
3. 署名・notarize し、notarization ticket を staple します
4. `Mytty.zip` を GitHub Releases に公開します

repository に署名または notarize 用の secret が無い場合、workflow は意図的に失敗します。署名なしの artifact にフォールバックすることはありません。

## 手動で tag を打つ場合

通常は `make release` を使いますが、同等の手順を手動で行うと次のようになります。

```sh
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

この flow で公開されるのは macOS app だけです。`ios/MyttyRemote` の iOS リモートアプリは Xcode Cloud 経由で別に公開されます。詳細は [iOS リモートアプリをビルドする](build-ios-remote-app_ja.md) を参照してください。
