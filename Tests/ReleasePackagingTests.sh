#!/bin/sh

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
plist="$root/Resources/Info.plist"
workflow="$root/.github/workflows/release.yml"
ghostty_action="$root/.github/actions/prepare-ghostty/action.yml"
bundle_script="$root/scripts/bundle.sh"
readme="$root/README.md"
readme_ja="$root/README_ja.md"
building="$root/docs/how-to/build-macos-app.md"
building_ja="$root/docs/how-to/build-macos-app_ja.md"

for document in "$readme" "$readme_ja" "$building" "$building_ja"; do
  test -f "$document"
done
grep -F '[日本語](README_ja.md)' "$readme" >/dev/null
for heading in '## Overview' '## Features' '## Documentation' '## Build'; do
  grep -F "$heading" "$readme" >/dev/null
done
grep -F '[English](README.md)' "$readme_ja" >/dev/null
for heading in '## 概要' '## 特徴' '## ドキュメント' '## ビルド方法'; do
  grep -F "$heading" "$readme_ja" >/dev/null
done
grep -F 'docs/how-to/build-macos-app.md' "$readme" >/dev/null
grep -F 'docs/how-to/build-macos-app_ja.md' "$readme_ja" >/dev/null

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$plist")" = "Mytty"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$plist")" = "Mytty"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")" = "Mytty"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist")" = "AppIcon"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:CFBundleTypeRole' "$plist")" = "Shell"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:0:LSItemContentTypes:0' "$plist")" = "public.unix-executable"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:1:LSItemContentTypes:0' "$plist")" = "public.folder"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:1:CFBundleTypeRole' "$plist")" = "Viewer"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes:1:LSHandlerRank' "$plist")" = "Alternate"
test "$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSMessage' "$plist")" = "openFolder"
test "$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSPortName' "$plist")" = "Mytty"
test "$(/usr/libexec/PlistBuddy -c 'Print :NSServices:0:NSSendFileTypes:0' "$plist")" = "public.folder"
grep -F 'Set :NSServices:0:NSPortName $APP_NAME' "$bundle_script" >/dev/null
grep -F 'Set :NSServices:0:NSMenuItem:default Open in $APP_NAME' \
    "$bundle_script" >/dev/null
grep -F 'tags: ["v*"]' "$workflow" >/dev/null
grep -F 'actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd' \
    "$workflow" >/dev/null
grep -F 'persist-credentials: false' "$workflow" >/dev/null
grep -F 'gh release create' "$workflow" >/dev/null
grep -F 'release:' "$root/Makefile" >/dev/null
grep -F 'scripts/release.sh "$(VERSION)"' "$root/Makefile" >/dev/null
for release_guard in \
  'git diff --quiet' \
  'git diff --cached --quiet' \
  'git push origin main' \
  'git tag -a "$tag"' \
  'git push origin "$tag"'; do
  grep -F "$release_guard" "$root/scripts/release.sh" >/dev/null
done
grep -F 'Signing and notarization secrets are required' "$workflow" >/dev/null
grep -F 'uses: ./.github/actions/prepare-ghostty' \
    "$workflow" >/dev/null
test -f "$ghostty_action"
for expected in \
  'actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9' \
  'Vendor/ghostty/macos/GhosttyKit.xcframework' \
  'Vendor/ghostty/zig-out' \
  "steps.cache.outputs.cache-hit != 'true'" \
  'scripts/build-ghostty.sh'; do
  if ! grep -F "$expected" "$ghostty_action" >/dev/null; then
    echo "Ghostty preparation action must include: $expected" >&2
    exit 1
  fi
done
for forbidden in '.build' 'Vendor/ghostty/.zig-cache' 'dist/Mytty.app'; do
  if grep -F "$forbidden" "$ghostty_action" >/dev/null; then
    echo "Ghostty cache must not include: $forbidden" >&2
    exit 1
  fi
done
if grep -F 'using ad-hoc signing' "$workflow" >/dev/null; then
  echo 'public releases must not fall back to ad-hoc signing' >&2
  exit 1
fi
if grep -E 'uses: [^@]+@(v[0-9]+|main|master)$' \
    "$root"/.github/workflows/*.yml >/dev/null; then
  echo 'GitHub Actions must be pinned to immutable commits' >&2
  exit 1
fi
test -x "$bundle_script"
grep -F '.executable(name: "Mytty", targets: ["MyTTYApp"])' \
    "$root/Package.swift" >/dev/null
grep -F 'cp "$BIN_DIR/Mytty" "$APP/Contents/MacOS/Mytty"' \
    "$bundle_script" >/dev/null
grep -F 'APP_NAME="Mytty Dev"' "$bundle_script" >/dev/null
grep -F 'BUNDLE_IDENTIFIER="com.m-tkg.mytty.dev"' \
    "$bundle_script" >/dev/null
grep -F 'Set :CFBundleDisplayName $APP_NAME' "$bundle_script" >/dev/null
grep -F 'Set :CFBundleIdentifier $BUNDLE_IDENTIFIER' \
    "$bundle_script" >/dev/null
grep -F '.executable(' "$root/Package.swift" >/dev/null
grep -F 'name: "mytty-clamshell-helper"' "$root/Package.swift" >/dev/null
grep -F 'cp "$BIN_DIR/mytty-clamshell-helper"' "$bundle_script" >/dev/null
grep -F 'CLAMSHELL_LABEL="$BUNDLE_IDENTIFIER.clamshelld"' \
    "$bundle_script" >/dev/null
grep -F 'Contents/Library/LaunchDaemons/$CLAMSHELL_LABEL.plist' \
    "$bundle_script" >/dev/null
grep -F '<key>BundleProgram</key>' "$bundle_script" >/dev/null
grep -F '<key>MachServices</key>' "$bundle_script" >/dev/null
grep -F 'cp "$ICONSET_SOURCE/1024.png" "$BUNDLED_ICON"' \
    "$bundle_script" >/dev/null
grep -F 'BUNDLED_ICON_UPDATED=true' "$bundle_script" >/dev/null
grep -F 'ARCH_FLAGS=(--arch arm64)' "$bundle_script" >/dev/null
if grep -F -- '--arch x86_64' "$bundle_script" >/dev/null; then
  echo 'release bundle must be Apple Silicon only' >&2
  exit 1
fi
grep -F -- '-Dxcframework-target=native' \
    "$root/scripts/build-ghostty.sh" >/dev/null
grep -F -- '-Demit-themes=true' \
    "$root/scripts/build-ghostty.sh" >/dev/null
grep -F -- '-Demit-terminfo=true' \
    "$root/scripts/build-ghostty.sh" >/dev/null
grep -F 'GHOSTTY_RESOURCES=' \
    "$bundle_script" >/dev/null
grep -F 'GHOSTTY_TERMINFO=' \
    "$bundle_script" >/dev/null
grep -F 'cp -R "$GHOSTTY_RESOURCES/." "$APP/Contents/Resources/ghostty/"' \
    "$bundle_script" >/dev/null
grep -F 'cp -R "$GHOSTTY_TERMINFO" "$APP/Contents/Resources/terminfo"' \
    "$bundle_script" >/dev/null
grep -F 'macos-arm64/libghostty-internal-fat.a' \
    "$root/scripts/build-ghostty.sh" >/dev/null
if grep -F -- 'verify_arch x86_64' \
    "$root/scripts/build-ghostty.sh" >/dev/null; then
  echo 'GhosttyKit must be Apple Silicon only' >&2
  exit 1
fi
if grep -F 'github.com/steipete/CodexBar' "$root/Package.swift" >/dev/null; then
  echo 'Mytty must not depend on CodexBar' >&2
  exit 1
fi
if grep -R -F 'import CodexBarCore' "$root/Sources/MyTTYApp" >/dev/null; then
  echo 'agent usage must be implemented inside Mytty' >&2
  exit 1
fi
if grep -R -F 'Bundle.module' "$root/Sources/MyTTYApp" >/dev/null; then
  echo 'release resources must not depend on the toolchain-specific Bundle.module accessor' >&2
  exit 1
fi
if grep -F 'import Security' \
    "$root/Sources/MyTTYApp/NativeAgentUsageLoader.swift" >/dev/null; then
  echo 'background usage loading must not block on Keychain UI' >&2
  exit 1
fi
"$root/Tests/SigningIdentityTests.sh"

printf 'Release packaging contract passed\n'
