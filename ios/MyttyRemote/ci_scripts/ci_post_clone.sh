#!/bin/sh
# Xcode Cloud clones the repository without running scripts/build-ghostty.sh,
# so the root package's GhosttyKit binary target has no artifact and package
# resolution fails before the iOS build even starts. The iOS app only links
# MyTTYRemoteKit, which never touches GhosttyKit, so a minimal stub artifact
# is enough to let resolution succeed. Skipped when a real artifact exists.
set -eu

repository="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../../.." && pwd)}"
xcframework="$repository/Vendor/ghostty/macos/GhosttyKit.xcframework"

if [ -f "$xcframework/Info.plist" ]; then
    echo "GhosttyKit.xcframework already present; leaving it alone."
    exit 0
fi

echo "Creating stub GhosttyKit.xcframework for package resolution."
mkdir -p "$xcframework/macos-arm64"
# An archive containing only the global header is a valid empty static
# library (macOS `ar` refuses to create one with no members).
printf '!<arch>\n' > "$xcframework/macos-arm64/libGhosttyKit.a"
cat > "$xcframework/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>LibraryIdentifier</key>
			<string>macos-arm64</string>
			<key>LibraryPath</key>
			<string>libGhosttyKit.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>macos</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
PLIST
