/**
 * Request authentication for `/v1/push`.
 *
 * A registration hands the phone a random `relaySecret`, which the phone
 * passes to its Mac over the already-encrypted pairing channel. Possession
 * of that secret is what authorises pushing to that registration — the
 * relay never sees the pairing key itself, so this is the only thing it
 * can check.
 */

/** How far a request timestamp may be from the relay's clock. Bounds
 *  replay of a captured request without demanding synchronised clocks. */
export const MAX_CLOCK_SKEW_SECONDS = 300;

export const MAX_BODY_BYTES = 4096;

export function randomSecretBase64() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

export function randomPushID() {
  return crypto.randomUUID();
}

function hex(buffer) {
  return [...new Uint8Array(buffer)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function signRequest({ secretBase64, timestamp, body }) {
  const secret = Uint8Array.from(atob(secretBase64), (character) =>
    character.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "raw",
    secret,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${timestamp}.${body}`),
  );
  return hex(signature);
}

/** Compares in constant time so a signature cannot be recovered by
 *  timing how long a guess takes to be rejected. */
export function secureEquals(left, right) {
  if (typeof left !== "string" || typeof right !== "string") return false;
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export function isFreshTimestamp(timestamp, now) {
  if (!Number.isFinite(timestamp)) return false;
  return Math.abs(now - timestamp) <= MAX_CLOCK_SKEW_SECONDS;
}

/** APNs device tokens are hex. Apple has never promised a width, so the
 *  bound is generous rather than pinned to today's 32 bytes. */
export function isValidDeviceToken(value) {
  return (
    typeof value === "string" &&
    value.length >= 32 &&
    value.length <= 200 &&
    /^[0-9a-fA-F]+$/.test(value)
  );
}

export function isValidEnvironment(value) {
  return value === "sandbox" || value === "production";
}
