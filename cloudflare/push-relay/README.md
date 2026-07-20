# Mytty push relay

A Cloudflare Worker that forwards Attention alerts from a Mac to APNs.

It exists so the APNs provider key does not have to live on every user's
Mac. An APNs key is bound to the App ID it was issued for, so only whoever
signed the iOS app can hold one — pushing that requirement onto users would
mean push only ever worked for people building the app themselves.

The relay is deliberately incurious. It stores a device token and a shared
secret per phone, and forwards an opaque blob:

```
Mac ──HTTPS──> Worker ──HTTP/2──> APNs ──> iPhone
               (.p8)                       └ notification service extension
                                             decrypts with the pairing key
```

Alert text is sealed on the Mac with the pairing key that Mac and phone
established when they paired, which the relay never sees. What reaches
Cloudflare is a device token, a random Mac identifier, and ciphertext. The
placeholder title and body in the payload are what a phone shows if it
cannot decrypt (an older build, or a Mac it has since unpaired).

## Endpoints

| Method | Path | Caller | Purpose |
| --- | --- | --- | --- |
| POST | `/v1/register` | iPhone | Exchanges an APNs device token for a `pushID` and `relaySecret`. |
| POST | `/v1/push` | Mac | Delivers one sealed alert, signed with the `relaySecret`. |

`/v1/register` is unauthenticated because there is nothing to authenticate:
the caller already holds the device token, and registering only creates a
mailbox for a phone they can already push to. `/v1/push` requires
`x-mytty-push-id`, `x-mytty-timestamp`, and `x-mytty-signature` — a
hex HMAC-SHA256 of `<timestamp>.<body>` under the registration's secret.
Timestamps more than five minutes from the relay's clock are refused, and
an unknown push ID answers exactly like a bad signature so live IDs cannot
be enumerated.

Registrations expire after 180 days of no deliveries, and are dropped
immediately when APNs reports the token is dead (`Unregistered`,
`BadDeviceToken`, `DeviceTokenNotForTopic`).

## Deploying

One-time, from this directory:

```sh
npx wrangler kv namespace create REGISTRATIONS
# put the printed id into wrangler.toml

npx wrangler secret put APNS_TEAM_ID       # 10 characters
npx wrangler secret put APNS_KEY_ID        # 10 characters, from AuthKey_XXXXXXXXXX.p8
npx wrangler secret put APNS_PRIVATE_KEY   # paste the whole .p8, BEGIN/END lines included

npx wrangler deploy
```

`APNS_TOPIC` in `wrangler.toml` must match the iOS app's bundle identifier,
and the key must belong to the team that signed it.

Then point the apps at the deployed Worker by setting `PushRelay.defaultURL`
in `Sources/MyTTYRemoteKit/PushRelay.swift` to its URL. Both the Mac app and
the iOS app read that one constant, so they cannot drift apart.

## Tests

```sh
npm test    # node --test, no dependencies
```

Covers the parts worth getting wrong: ES256 provider tokens (verified
against a real public key), request signing and its replay window, and
which APNs rejections are permanent. Routing itself is left to `wrangler
dev`.
