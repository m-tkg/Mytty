# Build the macOS app from source

## Requirements

- Apple Silicon Mac running macOS 15 or later
- Xcode toolchain with Swift 6.2 support
- Homebrew `zig@0.15`

The Zig version is what the pinned Ghostty submodule requires; `scripts/build-ghostty.sh` checks for it before building. Install it if you don't already have it.

```sh
brew install zig@0.15
```

## Build libghostty

Fetch the submodules and build Ghostty.

```sh
git submodule update --init --recursive
scripts/build-ghostty.sh
```

This produces `GhosttyKit.xcframework` plus the Ghostty themes, shell integration, and terminfo the application bundle needs. You don't need to run it before every build, only after changing the Ghostty revision.

## Build and test

```sh
swift build
swift test
Tests/ReleasePackagingTests.sh
```

Run `swift run Mytty` during development. The debug build is named **Mytty Dev**, shows a `DEV` Dock badge, and keeps its state in separate paths:

| Use | Path |
| --- | --- |
| Configuration | `~/.config/mytty-dev/` |
| Application data | `~/Library/Application Support/mytty-dev/` |
| Logs | `~/Library/Logs/mytty-dev/` |

Sockets are also created separately inside a temporary directory, so they never interfere with an installed release build. Only agent hook installation is shared, since each provider's hooks are written to a config file shared by the whole user.

## Package an application bundle

To bundle a debug build:

```sh
scripts/bundle.sh debug
open "dist/Mytty Dev.app"
```

To bundle a release build:

```sh
VERSION=0.1.0 BUILD_NUMBER=1 scripts/bundle.sh release
open dist/Mytty.app
```

It signs with a Developer ID identity if one can be found through `SIGN_IDENTITY` or `scripts/resolve-signing-identity.sh`, and falls back to an ad-hoc signature otherwise. An ad-hoc signature is fine for checking a build locally but can't be distributed to other Macs. Distributed builds go through the release workflow's signing and notarization instead; see [Release a version](release-a-version.md).

## Building without SIMD

`scripts/build-ghostty.sh` builds Ghostty's SIMD C++ sources by default. If a newer SDK or Zig toolchain can't compile them, run the script with `MYTTY_GHOSTTY_SIMD=false` to build the scalar paths instead. This only affects the vendor library build, not Mytty itself.

SIMD used to be off by default: the previously pinned Ghostty needed Zig 0.15.2, whose bundled libc++ couldn't compile these sources against the Xcode 27 beta SDK. With Zig 0.17 and the Xcode 27.2 SDK they compile.
