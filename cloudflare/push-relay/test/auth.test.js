import assert from "node:assert/strict";
import test from "node:test";

import {
  MAX_CLOCK_SKEW_SECONDS,
  isFreshTimestamp,
  isValidDeviceToken,
  isValidEnvironment,
  randomPushID,
  randomSecretBase64,
  secureEquals,
  signRequest,
} from "../src/auth.js";

test("a signature covers both the timestamp and the body", async () => {
  const secretBase64 = randomSecretBase64();
  const signature = await signRequest({
    secretBase64,
    timestamp: 1_700_000_000,
    body: '{"macID":"m"}',
  });

  assert.equal(
    await signRequest({
      secretBase64,
      timestamp: 1_700_000_000,
      body: '{"macID":"m"}',
    }),
    signature,
  );
  // Replaying the same body under a different timestamp must not verify.
  assert.notEqual(
    await signRequest({
      secretBase64,
      timestamp: 1_700_000_001,
      body: '{"macID":"m"}',
    }),
    signature,
  );
  // Nor may the body be swapped under a captured timestamp.
  assert.notEqual(
    await signRequest({
      secretBase64,
      timestamp: 1_700_000_000,
      body: '{"macID":"other"}',
    }),
    signature,
  );
});

test("a signature does not verify under a different secret", async () => {
  const body = '{"macID":"m"}';
  const first = await signRequest({
    secretBase64: randomSecretBase64(),
    timestamp: 1_700_000_000,
    body,
  });
  const second = await signRequest({
    secretBase64: randomSecretBase64(),
    timestamp: 1_700_000_000,
    body,
  });
  assert.notEqual(first, second);
});

test("timestamps outside the skew window are rejected", () => {
  const now = 1_700_000_000;
  assert.equal(isFreshTimestamp(now, now), true);
  assert.equal(isFreshTimestamp(now - MAX_CLOCK_SKEW_SECONDS, now), true);
  assert.equal(isFreshTimestamp(now + MAX_CLOCK_SKEW_SECONDS, now), true);
  assert.equal(isFreshTimestamp(now - MAX_CLOCK_SKEW_SECONDS - 1, now), false);
  assert.equal(isFreshTimestamp(now + MAX_CLOCK_SKEW_SECONDS + 1, now), false);
  assert.equal(isFreshTimestamp(Number.NaN, now), false);
});

test("comparison rejects mismatched values and lengths", () => {
  assert.equal(secureEquals("abc", "abc"), true);
  assert.equal(secureEquals("abc", "abd"), false);
  assert.equal(secureEquals("abc", "abcd"), false);
  assert.equal(secureEquals("abc", null), false);
  assert.equal(secureEquals(undefined, undefined), false);
});

test("device tokens must be hex of a plausible width", () => {
  assert.equal(isValidDeviceToken("a".repeat(64)), true);
  assert.equal(isValidDeviceToken("A1".repeat(32)), true);
  assert.equal(isValidDeviceToken("a".repeat(31)), false);
  assert.equal(isValidDeviceToken("a".repeat(201)), false);
  assert.equal(isValidDeviceToken(`${"a".repeat(63)}z`), false);
  assert.equal(isValidDeviceToken(null), false);
});

test("only the two APNs environments are accepted", () => {
  assert.equal(isValidEnvironment("sandbox"), true);
  assert.equal(isValidEnvironment("production"), true);
  assert.equal(isValidEnvironment("staging"), false);
});

test("issued identifiers and secrets are unique", () => {
  assert.notEqual(randomPushID(), randomPushID());
  assert.notEqual(randomSecretBase64(), randomSecretBase64());
  assert.equal(atob(randomSecretBase64()).length, 32);
});
