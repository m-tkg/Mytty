/**
 * APNs provider-token authentication and delivery.
 *
 * The relay exists so the `.p8` never has to live on a user's Mac; it is a
 * Worker secret here and nowhere else. Everything the relay learns about a
 * notification is the device token and an opaque ciphertext — the alert
 * text is sealed with the Mac/phone pairing key it does not have.
 */

const APNS_HOSTS = {
  sandbox: "api.sandbox.push.apple.com",
  production: "api.push.apple.com",
};

/** Apple rejects provider tokens older than an hour and rate-limits
 *  clients that mint a new one per push, so one is reused for 45 minutes. */
export const TOKEN_REFRESH_SECONDS = 45 * 60;

export function base64URL(bytes) {
  let binary = "";
  for (const byte of new Uint8Array(bytes)) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Strips the PEM armour off a `.p8` and imports it for ES256 signing. */
export async function importPrivateKey(pem) {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (character) =>
    character.charCodeAt(0),
  );
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

export async function makeProviderToken({ teamID, keyID, privateKeyPEM, issuedAt }) {
  const header = base64URL(
    new TextEncoder().encode(JSON.stringify({ alg: "ES256", kid: keyID })),
  );
  const claims = base64URL(
    new TextEncoder().encode(JSON.stringify({ iss: teamID, iat: issuedAt })),
  );
  const signingInput = `${header}.${claims}`;
  const key = await importPrivateKey(privateKeyPEM);
  // WebCrypto's ECDSA output is already the raw r||s pair JWS specifies.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64URL(signature)}`;
}

/**
 * The payload delivered to the phone. `mutable-content` lets the app's
 * notification service extension replace the placeholder title and body
 * with the decrypted ones; a phone that cannot decrypt (a build without
 * the extension, or a Mac it is no longer paired with) still shows
 * something truthful rather than nothing.
 */
export function buildPayload({ macID, ciphertext, placeholder }) {
  return {
    aps: {
      alert: { title: placeholder.title, body: placeholder.body },
      sound: "default",
      "mutable-content": 1,
      "interruption-level": "time-sensitive",
      "thread-id": "mytty-attention",
    },
    m: macID,
    c: ciphertext,
  };
}

export function apnsURL(environment, deviceToken) {
  const host = APNS_HOSTS[environment];
  if (!host) throw new Error(`unknown APNs environment: ${environment}`);
  return `https://${host}/3/device/${deviceToken}`;
}

/** The `reason` Apple returns for a rejection (`BadDeviceToken`, …). */
export function failureReason(text) {
  try {
    const parsed = JSON.parse(text);
    return typeof parsed?.reason === "string" ? parsed.reason : null;
  } catch {
    return null;
  }
}

/** True for rejections that mean the registration is dead for good, so
 *  the relay can drop it instead of retrying it forever. */
export function isPermanentFailure(status, reason) {
  if (status === 410) return true;
  return (
    status === 400 &&
    ["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"].includes(reason)
  );
}
