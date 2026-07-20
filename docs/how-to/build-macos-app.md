# Build the macOS app from source

This covers building Mytty locally: fetching libghostty, running the debug
binary, and packaging an application bundle.

## Requirements

- Apple Silicon Mac running macOS 15 or later
- Xcode toolchain with Swift 6.2 support
- Git
- Homebrew `zig@0.15`. The pinned Ghostty submodule requires this exact
  version, and `scripts/build-ghostty.sh` checks for it before building.

Install Zig if it is missing:

```sh
brew install zig@0.15
```

## Fetch and build libghostty

Clone with submodules, or initialize them after cloning:

```sh
git submodule update --init --recursive
scripts/build-ghostty.sh
```

The script produces the native arm64 `GhosttyKit.xcframework` plus Ghostty's
themes, shell integration, and terminfo, all of which the application bundle
needs. Re-run this step only after changing the Ghostty revision; it does not
need to run before every Swift build.

## Build and test

```sh
swift build
swift test
Tests/ReleasePackagingTests.sh
```

Run the app during development with `swift run Mytty`. This debug build
identifies itself as **Mytty Dev**, shows a `DEV` Dock badge, and keeps its
state under separate paths:

- `~/.config/mytty-dev/`
- `~/Library/Application Support/mytty-dev/`
- `~/Library/Logs/mytty-dev/`, plus a temporary socket namespace

An installed release build never sees this state. Agent hook installation
itself stays shared between the two, since the supported providers read their
hooks from global user configuration rather than per-build paths.

## Package an application bundle

A local debug bundle:

```sh
scripts/bundle.sh debug
open "dist/Mytty Dev.app"
```

An arm64 release bundle:

```sh
VERSION=0.1.0 BUILD_NUMBER=1 scripts/bundle.sh release
open dist/Mytty.app
```

`scripts/bundle.sh` signs with a Developer ID identity when `SIGN_IDENTITY` or
the configured signing resolver supplies one. Without one it falls back to an
ad-hoc signature, which is enough for local testing but not for anything
distributed to other machines. Public artifacts go through the release
workflow's signing and notarization instead, described in
[Release a version](release-a-version.md).

## Troubleshooting: SIMD build failure on Xcode 27 beta

The pinned Ghostty revision needs Zig 0.15.2, and its bundled libc++ fails to
compile Ghostty's SIMD C++ sources against the Xcode 27 beta SDK: that SDK no
longer exposes the `INFINITY` macro this compilation path expects.
`scripts/build-ghostty.sh` works around it by disabling SIMD by default, which
only affects the vendor library build, not the rest of Mytty. Once the pinned
toolchain moves past this beta SDK, set `MYTTY_GHOSTTY_SIMD=true` before
running the script to confirm the upstream SIMD path still builds.
