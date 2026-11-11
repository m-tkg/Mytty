#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ghostty_dir="$repo_root/Vendor/ghostty"
patch_file="$repo_root/Patches/ghostty-terminal-history.patch"
required_version=$(
    sed -n 's/.*\.minimum_zig_version = "\([^"]*\)".*/\1/p' \
        "$ghostty_dir/build.zig.zon"
)

find_zig() {
    if [ -n "${ZIG:-}" ]; then
        printf '%s\n' "$ZIG"
        return
    fi

    for candidate in \
        /opt/homebrew/opt/zig@0.17/bin/zig \
        /usr/local/opt/zig@0.17/bin/zig \
        "$(command -v zig 2>/dev/null || true)"
    do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            if [ "$($candidate version)" = "$required_version" ]; then
                printf '%s\n' "$candidate"
                return
            fi
        fi
    done

    return 1
}

zig=$(find_zig || true)
if [ -z "$zig" ]; then
    printf 'error: Ghostty requires Zig %s\n' "$required_version" >&2
    printf 'install it with: brew install zig@0.17 (or set ZIG to Zig %s)\n' "$required_version" >&2
    exit 1
fi

if git -C "$ghostty_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
    : # Patch is already applied in this working tree.
elif git -C "$ghostty_dir" apply --check "$patch_file"; then
    git -C "$ghostty_dir" apply "$patch_file"
else
    printf 'error: Ghostty terminal history patch does not apply cleanly\n' >&2
    exit 1
fi

# Ghostty's SIMD C++ sources are built by default, as upstream does. Set
# MYTTY_GHOSTTY_SIMD=false to fall back to the scalar paths if a newer SDK
# or Zig toolchain cannot compile them.
simd=${MYTTY_GHOSTTY_SIMD:-true}

(
    cd "$ghostty_dir"
    "$zig" build \
        -Demit-xcframework=true \
        -Dxcframework-target=native \
        -Doptimize=ReleaseFast \
        -Dsimd="$simd" \
        -Demit-exe=false \
        -Demit-macos-app=false \
        -Demit-terminfo=true \
        -Demit-termcap=false \
        -Demit-themes=true \
        -Demit-docs=false
)

library="$ghostty_dir/macos/GhosttyKit.xcframework/macos-arm64/libghostty-internal.a"
if [ ! -f "$library" ]; then
    printf 'error: GhosttyKit library was not produced\n' >&2
    exit 1
fi

lipo "$library" -verify_arch arm64
printf 'GhosttyKit ready: %s\n' "$library"
