import {
  TOKEN_REFRESH_SECONDS,
  apnsURL,
  buildPayload,
  failureReason,
  isPermanentFailure,
  makeProviderToken,
} from "./apns.js";
import {
  MAX_BODY_BYTES,
  isFreshTimestamp,
  isValidDeviceToken,
  isValidEnvironment,
  randomPushID,
  randomSecretBase64,
  secureEquals,
  signRequest,
} from "./auth.js";

/** Registrations expire if a Mac stops pushing to them entirely, so
 *  abandoned entries do not accumulate. Refreshed on every delivery. */
const REGISTRATION_TTL_SECONDS = 180 * 24 * 60 * 60;

/** How stale a registration's TTL may get before a delivery rewrites it.
 *  Rewriting on every push would spend a KV write per notification to
 *  move a 180-day expiry forward by minutes. */
const REGISTRATION_REFRESH_SECONDS = 24 * 60 * 60;

/** Cached across requests within one isolate; minting a provider token
 *  per push is what Apple returns TooManyProviderTokenUpdates for. The
 *  key id is part of the cache identity so that rotating the signing key
 *  cannot keep a token signed by the old one alive for another 45
 *  minutes in an isolate that outlived the secret update. */
let cachedToken = null;

async function providerToken(env, nowSeconds) {
  if (
    cachedToken &&
    cachedToken.keyID === env.APNS_KEY_ID &&
    nowSeconds - cachedToken.issuedAt < TOKEN_REFRESH_SECONDS
  ) {
    return cachedToken.value;
  }
  const value = await makeProviderToken({
    teamID: env.APNS_TEAM_ID,
    keyID: env.APNS_KEY_ID,
    privateKeyPEM: env.APNS_PRIVATE_KEY,
    issuedAt: nowSeconds,
  });
  cachedToken = { value, issuedAt: nowSeconds, keyID: env.APNS_KEY_ID };
  return value;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

/**
 * Issues a push identifier and the secret that authorises pushing to it.
 * Called by the phone itself, which is why it needs no authentication:
 * the only thing an attacker gains by registering is a mailbox for a
 * device token they already had to know.
 */
async function handleRegister(request, env, nowSeconds) {
  // Nothing authenticates this endpoint, so the only brake on someone
  // filling the namespace with junk registrations is a per-address limit.
  // Optional so tests and `wrangler dev` run without the binding.
  if (env.REGISTER_LIMITER) {
    const { success } = await env.REGISTER_LIMITER.limit({
      key: request.headers.get("cf-connecting-ip") ?? "unknown",
    });
    if (!success) return json({ error: "rate limited" }, 429);
  }

  const body = await request.json().catch(() => null);
  if (!body || !isValidDeviceToken(body.deviceToken)) {
    return json({ error: "invalid deviceToken" }, 400);
  }
  if (!isValidEnvironment(body.environment)) {
    return json({ error: "invalid environment" }, 400);
  }

  const pushID = randomPushID();
  const relaySecret = randomSecretBase64();
  await env.REGISTRATIONS.put(
    `push:${pushID}`,
    JSON.stringify({
      deviceToken: body.deviceToken,
      environment: body.environment,
      relaySecret,
      refreshedAt: nowSeconds,
    }),
    { expirationTtl: REGISTRATION_TTL_SECONDS },
  );
  return json({ pushID, relaySecret });
}

/**
 * Forwards one sealed alert. The Mac proves it holds the registration's
 * relay secret; the alert text inside `ciphertext` stays opaque to us.
 */
async function handlePush(request, env, nowSeconds) {
  const pushID = request.headers.get("x-mytty-push-id");
  const timestamp = Number(request.headers.get("x-mytty-timestamp"));
  const signature = request.headers.get("x-mytty-signature");
  if (!pushID || !signature || !isFreshTimestamp(timestamp, nowSeconds)) {
    return json({ error: "unauthorized" }, 401);
  }

  const raw = await request.text();
  // `raw.length` counts UTF-16 code units, which undercounts any
  // non-ASCII body by up to three times.
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) {
    return json({ error: "payload too large" }, 413);
  }

  const stored = await env.REGISTRATIONS.get(`push:${pushID}`, "json");
  // Same answer for "no such registration" and "bad signature", so this
  // cannot be used to enumerate live push IDs.
  if (!stored) return json({ error: "unauthorized" }, 401);
  const expected = await signRequest({
    secretBase64: stored.relaySecret,
    timestamp,
    body: raw,
  });
  if (!secureEquals(expected, signature)) {
    return json({ error: "unauthorized" }, 401);
  }

  // Authenticated, but still not trusted to be well-formed: a body that
  // is not a JSON object is the caller's mistake (400), not ours (500).
  let body = null;
  try {
    body = JSON.parse(raw);
  } catch {
    body = null;
  }
  if (
    !body ||
    typeof body.ciphertext !== "string" ||
    typeof body.macID !== "string"
  ) {
    return json({ error: "invalid payload" }, 400);
  }

  // A delivered push leaves no other trace, so "the Mac never sent one"
  // and "the Mac sent one that failed" are otherwise indistinguishable
  // from the outside. Expires after a day.
  await env.REGISTRATIONS.put(
    "debug:last-push",
    JSON.stringify({ at: new Date().toISOString(), macID: body.macID }),
    { expirationTtl: 24 * 60 * 60 },
  );

  const payload = buildPayload({
    macID: body.macID,
    ciphertext: body.ciphertext,
    placeholder: {
      title: typeof body.title === "string" ? body.title : "Mytty",
      body: typeof body.placeholder === "string" ? body.placeholder : "",
    },
  });

  const response = await fetch(
    apnsURL(stored.environment, stored.deviceToken),
    {
      method: "POST",
      headers: {
        authorization: `bearer ${await providerToken(env, nowSeconds)}`,
        "apns-topic": env.APNS_TOPIC,
        "apns-push-type": "alert",
        "apns-priority": "10",
        ...(typeof body.collapseID === "string"
          ? { "apns-collapse-id": body.collapseID }
          : {}),
      },
      body: JSON.stringify(payload),
    },
  );

  if (response.ok) {
    // Keep an actively used registration from ageing out. Registrations
    // written before `refreshedAt` existed count as due.
    const refreshedAt = Number.isFinite(stored.refreshedAt)
      ? stored.refreshedAt
      : 0;
    if (nowSeconds - refreshedAt >= REGISTRATION_REFRESH_SECONDS) {
      await env.REGISTRATIONS.put(
        `push:${pushID}`,
        JSON.stringify({ ...stored, refreshedAt: nowSeconds }),
        { expirationTtl: REGISTRATION_TTL_SECONDS },
      );
    }
    return json({ ok: true });
  }

  const reason = failureReason(await response.text());
  // The Mac only ever sees "rejected", and on its way to stderr at that,
  // so log what Apple actually said. Everything here is already ours or
  // Apple's own vocabulary; the device token is not included.
  console.log(
    `apns rejected status=${response.status} reason=${reason} ` +
      `environment=${stored.environment} topic=${env.APNS_TOPIC} ` +
      `tokenLength=${stored.deviceToken.length}`,
  );
  // Also parked in KV, because live log tailing is easy to miss and a
  // permanent failure deletes the registration that would have hinted at
  // what happened. Nothing here identifies the device: the token appears
  // only as a length. Expires after a day.
  await env.REGISTRATIONS.put(
    "debug:last-failure",
    JSON.stringify({
      at: new Date().toISOString(),
      status: response.status,
      reason,
      environment: stored.environment,
      topic: env.APNS_TOPIC,
      tokenLength: stored.deviceToken.length,
    }),
    { expirationTtl: 24 * 60 * 60 },
  );
  if (isPermanentFailure(response.status, reason)) {
    await env.REGISTRATIONS.delete(`push:${pushID}`);
  }
  return json({ error: reason ?? "apns rejected", status: response.status }, 502);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const nowSeconds = Math.floor(Date.now() / 1000);

    if (request.method === "POST" && url.pathname === "/v1/register") {
      return handleRegister(request, env, nowSeconds);
    }
    if (request.method === "POST" && url.pathname === "/v1/push") {
      return handlePush(request, env, nowSeconds);
    }
    return json({ error: "not found" }, 404);
  },
};
