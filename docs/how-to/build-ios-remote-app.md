# Build the iOS remote app

## Build for the simulator

```sh
make ios
```

This regenerates the Xcode project with XcodeGen and builds for the iOS
Simulator. For a real device, use `make ios-device`, but you need to set up
code signing first (see below).

## Required identifiers

This app ships a notification service extension that decrypts Attention
pushes before iOS displays them, so it needs two App IDs registered in the
Apple Developer portal, not just one.

| Identifier | Capability |
| --- | --- |
| `$(MYTTY_BUNDLE_ID)` | Push Notifications |
| `$(MYTTY_BUNDLE_ID).NotificationService` | none |

The extension itself needs no capability. It only receives notifications,
and the `keychain-access-groups` entitlement it uses to read the pairing
secret is satisfied by that entitlement alone, unlike App Groups.

## Changing the developer team

The signing defaults (`DEVELOPMENT_TEAM` and `MYTTY_BUNDLE_ID`) live in
`ios/MyttyRemote/Config/Signing.xcconfig`. Don't edit that file directly;
create `Config/Local.xcconfig` to override it instead.

```sh
cd ios/MyttyRemote
cp Config/Local.xcconfig.sample Config/Local.xcconfig
```

Then edit `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` and
`MYTTY_BUNDLE_ID` to your own values. Override `MYTTY_BUNDLE_ID`, not
`PRODUCT_BUNDLE_IDENTIFIER`.
