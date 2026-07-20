# Building Mytty

> **Building the iOS remote app with your own account?** Create
> `ios/MyttyRemote/Config/Local.xcconfig` first and set your own Team ID and
> bundle ID — see [Building with your own account](#building-with-your-own-account).
> Without it, a device build fails with nothing but a signing error.

## Requirements

- Apple Silicon Mac running macOS 15 or later
- Xcode toolchain with Swift 6.2 support
- Git
- The Zig version required by the pinned Ghostty submodule. The current build
  script looks for Homebrew `zig@0.15` and verifies the exact version.

Install Zig when necessary:

```sh
brew install zig@0.15
```

## Prepare libghostty

Clone with submodules, or initialize them after cloning:

```sh
git submodule update --init --recursive
scripts/build-ghostty.sh
```

The script builds the native arm64 `GhosttyKit.xcframework`, Ghostty themes,
shell integration, and terminfo required by the application bundle. See
[`ghostty-build.md`](ghostty-build.md) for the pinned-toolchain details and the
current SIMD compatibility switch.

Re-run this step after changing the Ghostty revision. It does not need to run
before every Swift build.

## Build and test

```sh
swift build
swift test
Tests/ReleasePackagingTests.sh
```

Run the executable during development with:

```sh
swift run Mytty
```

A debug execution identifies itself as **Mytty Dev**, displays a `DEV` Dock
badge, and uses these locations:

- `~/.config/mytty-dev/`
- `~/Library/Application Support/mytty-dev/`
- `~/Library/Logs/mytty-dev/`
- a temporary socket under `com.m-tkg.mytty.dev/`

This keeps an installed release's settings and sessions unchanged. Agent hook
installation remains shared because the supported providers use global user
configuration; each terminal pane still supplies its own event socket.

## Build an application bundle

Create a local debug bundle:

```sh
scripts/bundle.sh debug
open "dist/Mytty Dev.app"
```

Create an arm64 release bundle:

```sh
VERSION=0.1.0 BUILD_NUMBER=1 scripts/bundle.sh release
open dist/Mytty.app
```

The script uses a matching Developer ID identity when `SIGN_IDENTITY` or the
configured signing identity resolver supplies one. Otherwise it applies an
ad-hoc signature suitable for local testing. Public artifacts must be signed
and notarized by the release workflow.

## Release flow

Pushing a `v*` tag starts [the release workflow](../.github/workflows/release.yml).
The workflow runs the Swift and packaging tests, builds an Apple Silicon app,
signs and notarizes it, staples the notarization ticket, and publishes
`Mytty.zip` to GitHub Releases. It intentionally fails when the repository's
signing or notarization secrets are unavailable.

For example:

```sh
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

`make release VERSION=x.y.z` (`scripts/release.sh`) wraps this: it runs the
test suite locally, then pushes `main` and an annotated tag. A version with a
pre-release suffix (`x.y.z-beta.1`, `x.y.z-rc.2`, ...) tags and publishes a
GitHub pre-release instead of a stable release — the workflow detects the
suffix and passes `--prerelease` to `gh release create`. The accepted suffix
format matches what `ApplicationVersion` (`Sources/MyTTYApp/ApplicationUpdate.swift`)
can parse, so any tag this script accepts is one the in-app updater can also
resolve.

## iOS remote app

The companion iOS app lives in `ios/MyttyRemote` and is not part of the Mac
release flow. `make ios` regenerates the Xcode project with XcodeGen and
builds for the iOS Simulator; `make ios-device` builds for a real device,
which requires code signing.

### Required identifiers

The app ships a notification service extension, which decrypts Attention
pushes before iOS displays them. That means two App IDs have to exist in
the Apple Developer portal, not one:

| Identifier | Capabilities |
| --- | --- |
| `$(MYTTY_BUNDLE_ID)` | **Push Notifications** |
| `$(MYTTY_BUNDLE_ID).NotificationService` | none |

The extension needs no capabilities of its own: it receives notifications
rather than sending them, and `keychain-access-groups` — how it reads the
pairing secrets — is satisfied by the entitlement alone, unlike App Groups.

**Xcode Cloud does not create identifiers.** It manages signing, but an App
ID that does not exist yet is not registered for you, so a build can pass
locally (where automatic signing may create one on demand) and still fail
in Xcode Cloud. The symptom is `xcodebuild -exportArchive` exiting with
code 70 for every distribution method at once, while the archive step
itself succeeds — export cannot sign the embedded extension.

### Building with your own account

Signing defaults (`DEVELOPMENT_TEAM` / `MYTTY_BUNDLE_ID`) live in
`ios/MyttyRemote/Config/Signing.xcconfig`. Do not edit that file — create
`Config/Local.xcconfig` to override it:

```sh
cd ios/MyttyRemote
cp Config/Local.xcconfig.sample Config/Local.xcconfig
# Set DEVELOPMENT_TEAM and MYTTY_BUNDLE_ID to your own values
```

`Config/Local.xcconfig` is gitignored and XcodeGen does not read it, so
tracked files never show a diff. Override `MYTTY_BUNDLE_ID` rather than
`PRODUCT_BUNDLE_IDENTIFIER`: the notification service extension derives its
own identifier from it, so setting the latter directly would leave the
extension on the original team's id. Always change the bundle ID together
with the team: the default bundle ID is registered to the original team and
cannot be provisioned by another account. Note that a free Personal Team
may not be able to provision every capability.
