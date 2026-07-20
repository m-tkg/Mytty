import assert from "node:assert/strict";
import test from "node:test";

import {
  apnsURL,
  base64URL,
  buildPayload,
  failureReason,
  isPermanentFailure,
  makeProviderToken,
} from "../src/apns.js";

/** A throwaway P-256 key exported as PKCS#8 PEM, the same shape Apple's
 *  `.p8` download has, so no real provider key is involved. */
async function makeTestKeyPEM() {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const body = btoa(String.fromCharCode(...new Uint8Array(pkcs8)));
  const lines = body.match(/.{1,64}/g).join("\n");
  return {
    pem: `-----BEGIN PRIVATE KEY-----\n${lines}\n-----END PRIVATE KEY-----`,
    publicKey: pair.publicKey,
  };
}

function decodeSegment(segment) {
  const padded = segment.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(padded));
}

test("mints a provider token Apple's ES256 rules can verify", async () => {
  const { pem, publicKey } = await makeTestKeyPEM();

  const token = await makeProviderToken({
    teamID: "ABCDE12345",
    keyID: "FGHIJ67890",
    privateKeyPEM: pem,
    issuedAt: 1_700_000_000,
  });

  const [header, claims, signature] = token.split(".");
  assert.deepEqual(decodeSegment(header), { alg: "ES256", kid: "FGHIJ67890" });
  assert.deepEqual(decodeSegment(claims), {
    iss: "ABCDE12345",
    iat: 1_700_000_000,
  });
  assert.equal(token.includes("="), false);

  const raw = signature.replace(/-/g, "+").replace(/_/g, "/");
  const verified = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    Uint8Array.from(atob(raw), (character) => character.charCodeAt(0)),
    new TextEncoder().encode(`${header}.${claims}`),
  );
  assert.equal(verified, true);
});

test("base64url output carries no padding or URL-unsafe characters", () => {
  const encoded = base64URL(new Uint8Array([251, 255, 190, 0]));
  assert.equal(/^[A-Za-z0-9_-]+$/.test(encoded), true);
});

test("the payload keeps the alert text opaque and asks for mutation", () => {
  const payload = buildPayload({
    macID: "mac-1",
    ciphertext: "c2VhbGVk",
    placeholder: { title: "Mytty", body: "An agent needs you" },
  });

  assert.equal(payload.aps["mutable-content"], 1);
  assert.equal(payload.aps["interruption-level"], "time-sensitive");
  assert.equal(payload.m, "mac-1");
  assert.equal(payload.c, "c2VhbGVk");
  // The placeholder is all a phone without the extension ever sees, so it
  // must not be empty or leak anything specific.
  assert.equal(payload.aps.alert.title, "Mytty");
  assert.equal(payload.aps.alert.body, "An agent needs you");
  assert.equal(JSON.stringify(payload).includes("sealed"), false);
});

test("routes to the host matching the token's environment", () => {
  assert.equal(
    apnsURL("production", "abc"),
    "https://api.push.apple.com/3/device/abc",
  );
  assert.equal(
    apnsURL("sandbox", "abc"),
    "https://api.sandbox.push.apple.com/3/device/abc",
  );
  assert.throws(() => apnsURL("staging", "abc"));
});

test("extracts Apple's rejection reason when there is one", () => {
  assert.equal(failureReason('{"reason":"BadDeviceToken"}'), "BadDeviceToken");
  assert.equal(failureReason("not json"), null);
  assert.equal(failureReason("{}"), null);
});

test("only unrecoverable rejections drop the registration", () => {
  assert.equal(isPermanentFailure(410, "Unregistered"), true);
  assert.equal(isPermanentFailure(400, "BadDeviceToken"), true);
  assert.equal(isPermanentFailure(400, "DeviceTokenNotForTopic"), true);
  // A bad provider token or an Apple outage is our problem, not the
  // phone's — dropping the registration there would be unrecoverable.
  assert.equal(isPermanentFailure(403, "InvalidProviderToken"), false);
  assert.equal(isPermanentFailure(500, null), false);
  assert.equal(isPermanentFailure(429, "TooManyRequests"), false);
});
