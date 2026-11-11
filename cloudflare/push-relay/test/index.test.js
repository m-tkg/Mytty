import assert from "node:assert/strict";
import test from "node:test";

import worker from "../src/index.js";
import { MAX_BODY_BYTES, randomSecretBase64, signRequest } from "../src/auth.js";

const DAY_SECONDS = 24 * 60 * 60;

/** An in-memory stand-in for the KV namespace that records every write. */
function makeKV(initial = {}) {
  const store = new Map(Object.entries(initial));
  const puts = [];
  return {
    store,
    puts,
    async get(key) {
      return store.has(key) ? JSON.parse(store.get(key)) : null;
    },
    async put(key, value) {
      puts.push(key);
      store.set(key, value);
    },
    async delete(key) {
      store.delete(key);
    },
  };
}

function registration(overrides = {}) {
  return {
    deviceToken: "a".repeat(64),
    environment: "sandbox",
    relaySecret: randomSecretBase64(),
    ...overrides,
  };
}

async function pushRequest(pushID, secretBase64, raw) {
  const timestamp = Math.floor(Date.now() / 1000);
  const signature = await signRequest({ secretBase64, timestamp, body: raw });
  return new Request("https://relay.example/v1/push", {
    method: "POST",
    body: raw,
    headers: {
      "x-mytty-push-id": pushID,
      "x-mytty-timestamp": String(timestamp),
      "x-mytty-signature": signature,
    },
  });
}

function registerRequest(address = "203.0.113.7") {
  return new Request("https://relay.example/v1/register", {
    method: "POST",
    body: JSON.stringify({
      deviceToken: "b".repeat(64),
      environment: "production",
    }),
    headers: { "cf-connecting-ip": address },
  });
}

test("a signed body that is not a JSON object is a 400", async () => {
  const stored = registration();
  const kv = makeKV({ "push:p1": JSON.stringify(stored) });
  for (const raw of ["not json", "null", "[]", "{}"]) {
    const response = await worker.fetch(
      await pushRequest("p1", stored.relaySecret, raw),
      { REGISTRATIONS: kv },
    );
    assert.equal(response.status, 400, raw);
  }
});

test("the body limit counts bytes, not UTF-16 code units", async () => {
  const stored = registration();
  const kv = makeKV({ "push:p1": JSON.stringify(stored) });
  // Three bytes per character in UTF-8, one code unit each in a JS
  // string: under the limit by length, well over it on the wire.
  const raw = JSON.stringify({
    macID: "m",
    ciphertext: "あ".repeat(MAX_BODY_BYTES / 2),
  });
  assert.ok(raw.length <= MAX_BODY_BYTES);
  const response = await worker.fetch(
    await pushRequest("p1", stored.relaySecret, raw),
    { REGISTRATIONS: kv },
  );
  assert.equal(response.status, 413);
});

test("a delivery only rewrites a registration that is due a refresh", async (t) => {
  t.mock.method(globalThis, "fetch", async () => new Response(null, { status: 200 }));
  const now = Math.floor(Date.now() / 1000);
  const env = (kv) => ({
    REGISTRATIONS: kv,
    APNS_TOPIC: "topic",
    APNS_KEY_ID: "KEY",
    APNS_TEAM_ID: "TEAM",
    APNS_PRIVATE_KEY: TEST_KEY,
  });
  const raw = JSON.stringify({ macID: "m", ciphertext: "c" });

  const fresh = registration({ refreshedAt: now - 60 });
  const freshKV = makeKV({ "push:p1": JSON.stringify(fresh) });
  const first = await worker.fetch(
    await pushRequest("p1", fresh.relaySecret, raw),
    env(freshKV),
  );
  assert.equal(first.status, 200);
  assert.ok(!freshKV.puts.includes("push:p1"));

  // Registrations written before `refreshedAt` existed count as due.
  for (const stale of [
    registration({ refreshedAt: now - 2 * DAY_SECONDS }),
    registration(),
  ]) {
    const staleKV = makeKV({ "push:p1": JSON.stringify(stale) });
    const response = await worker.fetch(
      await pushRequest("p1", stale.relaySecret, raw),
      env(staleKV),
    );
    assert.equal(response.status, 200);
    assert.ok(staleKV.puts.includes("push:p1"));
    const rewritten = JSON.parse(staleKV.store.get("push:p1"));
    assert.ok(rewritten.refreshedAt >= now);
    assert.equal(rewritten.relaySecret, stale.relaySecret);
  }
});

test("registration is refused once the caller is rate limited", async () => {
  const kv = makeKV();
  const keys = [];
  const limiter = (success) => ({
    async limit({ key }) {
      keys.push(key);
      return { success };
    },
  });

  const allowed = await worker.fetch(registerRequest(), {
    REGISTRATIONS: kv,
    REGISTER_LIMITER: limiter(true),
  });
  assert.equal(allowed.status, 200);
  assert.equal(kv.puts.length, 1);

  const refused = await worker.fetch(registerRequest(), {
    REGISTRATIONS: kv,
    REGISTER_LIMITER: limiter(false),
  });
  assert.equal(refused.status, 429);
  assert.equal(kv.puts.length, 1);
  assert.deepEqual(keys, ["203.0.113.7", "203.0.113.7"]);
});

test("registration works without a rate limit binding", async () => {
  const kv = makeKV();
  const response = await worker.fetch(registerRequest(), { REGISTRATIONS: kv });
  assert.equal(response.status, 200);
  const body = await response.json();
  const stored = JSON.parse(kv.store.get(`push:${body.pushID}`));
  assert.equal(stored.relaySecret, body.relaySecret);
  assert.ok(Number.isFinite(stored.refreshedAt));
});

// A throwaway P-256 key, generated for these tests only.
const TEST_KEY = await (async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  return `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`;
})();
