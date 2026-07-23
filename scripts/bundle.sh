#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
GHOSTTY_RESOURCES="$ROOT/Vendor/ghostty/zig-out/share/ghostty"
GHOSTTY_TERMINFO="$ROOT/Vendor/ghostty/zig-out/share/terminfo"

if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
  echo "error: configuration must be debug or release" >&2
  exit 1
fi

if [[ "$CONFIG" == "debug" ]]; then
  APP_NAME="Mytty Dev"
  BUNDLE_IDENTIFIER="com.m-tkg.mytty.dev"
else
  APP_NAME="Mytty"
  BUNDLE_IDENTIFIER="com.m-tkg.mytty"
fi
APP="$OUTPUT_DIR/$APP_NAME.app"

case "$VERSION" in
  ""|*[!0-9A-Za-z.-]*)
    echo "error: invalid version: $VERSION" >&2
    exit 1
    ;;
esac

ARCH_FLAGS=()
if [[ "$CONFIG" == "release" ]]; then
  ARCH_FLAGS=(--arch arm64)
fi

echo "==> Building Mytty ($CONFIG)"
swift build \
  --package-path "$ROOT" \
  -c "$CONFIG" \
  "${ARCH_FLAGS[@]}"
BIN_DIR="$(
  swift build \
    --package-path "$ROOT" \
    -c "$CONFIG" \
    "${ARCH_FLAGS[@]}" \
    --show-bin-path
)"

echo "==> Bundling $APP"
for RESOURCE_DIRECTORY in \
  "$GHOSTTY_RESOURCES/themes" \
  "$GHOSTTY_RESOURCES/shell-integration" \
  "$GHOSTTY_TERMINFO"; do
  if [[ ! -d "$RESOURCE_DIRECTORY" ]]; then
    echo "error: Ghostty resource was not built: $RESOURCE_DIRECTORY" >&2
    exit 1
  fi
done
rm -rf "$APP"
mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Helpers" \
  "$APP/Contents/Resources/ghostty"
cp "$BIN_DIR/Mytty" "$APP/Contents/MacOS/Mytty"
cp "$BIN_DIR/mytty-agent-hook" "$APP/Contents/Helpers/mytty-agent-hook"
cp "$BIN_DIR/mytty-ctl" "$APP/Contents/Helpers/mytty-ctl"
cp "$BIN_DIR/mytty-clamshell-helper" \
  "$APP/Contents/MacOS/mytty-clamshell-helper"

# The privileged clamshell daemon (SMAppService): label and mach service
# name derive from the bundle identifier so dev and release bundles each
# register their own daemon.
CLAMSHELL_LABEL="$BUNDLE_IDENTIFIER.clamshelld"
mkdir -p "$APP/Contents/Library/LaunchDaemons"
cat > "$APP/Contents/Library/LaunchDaemons/$CLAMSHELL_LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$CLAMSHELL_LABEL</string>
	<key>BundleProgram</key>
	<string>Contents/MacOS/mytty-clamshell-helper</string>
	<key>MachServices</key>
	<dict>
		<key>$CLAMSHELL_LABEL</key>
		<true/>
	</dict>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>$BUNDLE_IDENTIFIER</string>
	</array>
</dict>
</plist>
PLIST
cp -R \
  "$BIN_DIR/mytty_MyTTYApp.bundle" \
  "$APP/Contents/Resources/mytty_MyTTYApp.bundle"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$GHOSTTY_RESOURCES/." "$APP/Contents/Resources/ghostty/"
cp -R "$GHOSTTY_TERMINFO" "$APP/Contents/Resources/terminfo"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleName $APP_NAME" \
  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleDisplayName $APP_NAME" \
  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" \
  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $VERSION" \
  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleVersion $BUILD_NUMBER" \
  "$APP/Contents/Info.plist"
# The Finder service advertises the app it belongs to: NSPortName must match
# CFBundleName, and the menu title must distinguish dev from release.
/usr/libexec/PlistBuddy \
  -c "Set :NSServices:0:NSPortName $APP_NAME" \
  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :NSServices:0:NSMenuItem:default Open in $APP_NAME" \
  "$APP/Contents/Info.plist"

ICONSET_SOURCE="$ROOT/Resources/AppIcon.appiconset"
ICON_SOURCE="$ROOT/Sources/MyTTYApp/Resources/AppIcon.png"
if [[ -d "$ICONSET_SOURCE" ]]; then
  BUNDLED_ICON_UPDATED=false
  for BUNDLED_ICON in \
    "$APP/Contents/Resources/mytty_MyTTYApp.bundle/AppIcon.png" \
    "$APP/Contents/Resources/mytty_MyTTYApp.bundle/Contents/Resources/AppIcon.png"; do
    if [[ -f "$BUNDLED_ICON" ]]; then
      cp "$ICONSET_SOURCE/1024.png" "$BUNDLED_ICON"
      BUNDLED_ICON_UPDATED=true
    fi
  done
  if [[ "$BUNDLED_ICON_UPDATED" != true ]]; then
    echo "error: bundled application icon resource was not found" >&2
    exit 1
  fi

  echo "==> Generating AppIcon.icns from AppIcon.appiconset"
  ICON_WORK="$(mktemp -d)"
  trap 'rm -rf "$ICON_WORK"' EXIT
  ICONSET="$ICON_WORK/AppIcon.iconset"
  mkdir -p "$ICONSET"
  cp "$ICONSET_SOURCE/16.png" "$ICONSET/icon_16x16.png"
  cp "$ICONSET_SOURCE/32.png" "$ICONSET/icon_16x16@2x.png"
  cp "$ICONSET_SOURCE/32.png" "$ICONSET/icon_32x32.png"
  cp "$ICONSET_SOURCE/64.png" "$ICONSET/icon_32x32@2x.png"
  cp "$ICONSET_SOURCE/128.png" "$ICONSET/icon_128x128.png"
  cp "$ICONSET_SOURCE/256.png" "$ICONSET/icon_128x128@2x.png"
  cp "$ICONSET_SOURCE/256.png" "$ICONSET/icon_256x256.png"
  cp "$ICONSET_SOURCE/512.png" "$ICONSET/icon_256x256@2x.png"
  cp "$ICONSET_SOURCE/512.png" "$ICONSET/icon_512x512.png"
  cp "$ICONSET_SOURCE/1024.png" "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
elif [[ -f "$ICON_SOURCE" ]]; then
  echo "==> Generating AppIcon.icns"
  ICON_WORK="$(mktemp -d)"
  trap 'rm -rf "$ICON_WORK"' EXIT
  ICONSET="$ICON_WORK/AppIcon.iconset"
  SQUARE="$ICON_WORK/AppIcon-square.png"
  mkdir -p "$ICONSET"
  WIDTH="$(sips -g pixelWidth "$ICON_SOURCE" | awk '/pixelWidth/ { print $2 }')"
  HEIGHT="$(sips -g pixelHeight "$ICON_SOURCE" | awk '/pixelHeight/ { print $2 }')"
  if (( WIDTH < HEIGHT )); then EDGE="$WIDTH"; else EDGE="$HEIGHT"; fi
  sips -c "$EDGE" "$EDGE" "$ICON_SOURCE" --out "$SQUARE" >/dev/null
  for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$SQUARE" \
      --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    RETINA=$((SIZE * 2))
    sips -z "$RETINA" "$RETINA" "$SQUARE" \
      --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Finder metadata on copied resources (e.g. an icon PNG previewed in
# Finder) makes codesign reject the bundle as "detritus"; strip it.
xattr -cr "$APP"

SIGN_IDENTITY="$("$ROOT/scripts/resolve-signing-identity.sh")"
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> Signing with $SIGN_IDENTITY"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Helpers/mytty-agent-hook"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Helpers/mytty-ctl"
  codesign --force --options runtime --timestamp \
    --identifier "$CLAMSHELL_LABEL" \
    --sign "$SIGN_IDENTITY" \
    "$APP/Contents/MacOS/mytty-clamshell-helper"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP"
else
  echo "==> Applying ad-hoc signature"
  codesign --force --options runtime --sign - \
    "$APP/Contents/Helpers/mytty-agent-hook"
  codesign --force --options runtime --sign - \
    "$APP/Contents/Helpers/mytty-ctl"
  codesign --force --options runtime \
    --identifier "$CLAMSHELL_LABEL" \
    --sign - \
    "$APP/Contents/MacOS/mytty-clamshell-helper"
  codesign --force --options runtime --sign - "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"
echo "==> Done: $APP"
