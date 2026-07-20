# Build the iOS remote app

The companion iOS app lives in `ios/MyttyRemote` and ships separately from
the Mac app, through Xcode Cloud rather than `scripts/release.sh`. This is
how to build it locally, including with your own Apple Developer account.

## Building for the simulator

```sh
make ios
```

This regenerates the Xcode project with XcodeGen and builds for the iOS
Simulator. `make ios-device` builds for a real device instead, which needs
code signing to be set up first (see below).

Whenever you add or remove a Swift file under `ios/MyttyRemote`, run
`make ios` again and commit the regenerated `project.pbxproj` alongside the
file. Xcode Cloud builds the checked-in project rather than running
XcodeGen itself, so a missing regeneration fails there with "Cannot find …
in scope" even though a local build worked.

## Required identifiers

The app ships a notification service extension that decrypts Attention
pushes before iOS displays them, so two App IDs need to exist in the Apple
Developer portal, not one:

| Identifier | Capabilities |
| --- | --- |
| `$(MYTTY_BUNDLE_ID)` | Push Notifications |
| `$(MYTTY_BUNDLE_ID).NotificationService` | none |

The extension itself needs no capabilities: it only receives notifications,
and the `keychain-access-groups` entitlement it uses to read the pairing
secrets is satisfied by the entitlement alone, unlike App Groups.

Xcode Cloud does not create identifiers for you. It manages signing, but an
App ID that doesn't exist yet isn't registered automatically. A build can
therefore succeed locally, where automatic signing may create one on demand,
and still fail in Xcode Cloud. The symptom is `xcodebuild -exportArchive`
exiting with code 70 for every distribution method at once, while the
archive step itself succeeds; export cannot sign the embedded extension
without a registered identifier.

## Building with your own account

Signing defaults (`DEVELOPMENT_TEAM` and `MYTTY_BUNDLE_ID`) live in
`ios/MyttyRemote/Config/Signing.xcconfig`. Don't edit that file directly;
create `Config/Local.xcconfig` to override it instead:

```sh
cd ios/MyttyRemote
cp Config/Local.xcconfig.sample Config/Local.xcconfig
```

Then edit `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` and
`MYTTY_BUNDLE_ID` to your own values. `Config/Local.xcconfig` is gitignored
and XcodeGen never reads it, so tracked files never show a diff from this.

Override `MYTTY_BUNDLE_ID`, not `PRODUCT_BUNDLE_IDENTIFIER`. The
notification service extension derives its own identifier from
`MYTTY_BUNDLE_ID`, so setting `PRODUCT_BUNDLE_IDENTIFIER` directly would
change the app's bundle ID while leaving the extension registered under the
original team's identifier, which cannot be signed by your team.

Always change the bundle ID together with the team: the default bundle ID is
registered to the original team and cannot be provisioned by another
account. A free Personal Team may also be unable to provision every
capability the app needs, notably Push Notifications.
