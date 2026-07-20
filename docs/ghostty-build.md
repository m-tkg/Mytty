# Ghostty Build

Ghostty is pinned as a Git submodule at `Vendor/ghostty`. Initialize it with:

```sh
git submodule update --init --recursive
```

Build the Apple Silicon macOS XCFramework with:

```sh
scripts/build-ghostty.sh
```

The script reads the required Zig version from Ghostty's `build.zig.zon` and
uses a matching `zig@0.15` Homebrew installation without changing the user's
global Zig selection.

## Xcode 27 beta

The accepted Ghostty revision requires Zig 0.15.2. Its bundled libc++ fails to
compile Ghostty's SIMD C++ sources against the Xcode 27 beta SDK because the
SDK no longer provides the expected `INFINITY` macro in that compilation path.

`scripts/build-ghostty.sh` therefore builds Ghostty with SIMD disabled by
default. This affects only the vendor library build and is a temporary
toolchain compatibility measure. Set `MYTTY_GHOSTTY_SIMD=true` to verify the
upstream SIMD path after upgrading the pinned Ghostty toolchain.
