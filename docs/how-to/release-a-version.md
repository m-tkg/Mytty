# Release a version

Mytty ships through a tag-triggered GitHub Actions workflow. This is how to
cut a release, including a pre-release, from a clean `main`.

## Run the release script

```sh
make release VERSION=x.y.z
```

This wraps `scripts/release.sh`: it runs the local test suite, then pushes
`main` and an annotated tag. Run it from a clean working tree; the script
does not attempt to reconcile local changes with what it pushes.

A version with a pre-release suffix publishes a GitHub pre-release instead of
a stable one:

```sh
make release VERSION=x.y.z-beta.1
```

The workflow detects the suffix and passes `--prerelease` to
`gh release create`. Only suffix formats that
`ApplicationVersion` (`Sources/MyTTYApp/ApplicationUpdate.swift`) can parse
are accepted, so any tag `scripts/release.sh` lets through is one the in-app
updater can also resolve later. The in-app updater only offers pre-releases
to a user who Option-clicks **Check for Updates**; a plain check and the
automatic launch/About checks stay on stable releases.

## What the workflow does

Pushing a `v*` tag starts
[the release workflow](../../.github/workflows/release.yml), which:

1. runs `swift test` and `Tests/ReleasePackagingTests.sh`
2. builds an Apple Silicon app
3. signs and notarizes it, then staples the notarization ticket
4. publishes `Mytty.zip` to GitHub Releases

The workflow fails intentionally when the repository's signing or
notarization secrets are unavailable, rather than falling back to an
unsigned artifact.

## Tagging manually

`make release` is the normal path, but the equivalent manual steps are:

```sh
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

Only the macOS app ships through this flow. The iOS remote app in
`ios/MyttyRemote` ships through Xcode Cloud instead. See
[Build the iOS remote app](build-ios-remote-app.md).
