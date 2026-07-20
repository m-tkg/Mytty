# Build entry points for the Mytty macOS app and the MyttyRemote iOS app.
#
#   make mac              debug build of the SwiftPM executable (.build/debug/Mytty)
#   make mac-app          packaged Mytty Dev.app in dist/ (debug)
#   make mac-release      packaged Mytty.app in dist/ (release, signed if possible)
#   make release VERSION=x.y.z  test, push main, and trigger a tagged release
#     VERSION may carry a pre-release suffix (e.g. x.y.z-beta.1) to publish
#     a GitHub pre-release instead of a stable release
#   make ios              iOS Simulator build
#   make ios-device       iOS device build (signed with the registered team)
#   make test             run the SwiftPM test suite
#   make clean            remove build products

IOS_DIR := ios/MyttyRemote
IOS_PROJECT := $(IOS_DIR)/MyttyRemote.xcodeproj
IOS_SCHEME := MyttyRemote
IOS_SIMULATOR ?= iPhone 17 Pro Max
VERSION ?= 0.1.0
BUILD_NUMBER ?= 1

.PHONY: all mac mac-app mac-release release ios ios-device ios-project test clean

all: mac ios

mac:
	swift build

mac-app:
	scripts/bundle.sh debug

mac-release:
	VERSION=$(VERSION) BUILD_NUMBER=$(BUILD_NUMBER) scripts/bundle.sh release

release:
	@if [ "$(origin VERSION)" != "command line" ]; then \
		echo 'error: specify a release version: make release VERSION=x.y.z' >&2; \
		exit 1; \
	fi
	scripts/release.sh "$(VERSION)"

# xcodegen keeps the Xcode project in sync with project.yml; regenerate
# before every iOS build so new source files are always picked up.
ios-project:
	cd $(IOS_DIR) && xcodegen generate

ios: ios-project
	xcodebuild \
		-project $(IOS_PROJECT) \
		-scheme $(IOS_SCHEME) \
		-destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
		build

ios-device: ios-project
	xcodebuild \
		-project $(IOS_PROJECT) \
		-scheme $(IOS_SCHEME) \
		-destination 'generic/platform=iOS' \
		-allowProvisioningUpdates \
		build

test:
	swift test

clean:
	swift package clean
	rm -rf dist
