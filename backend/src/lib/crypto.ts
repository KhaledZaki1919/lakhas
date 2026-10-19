/** Web Crypto helpers (ADR-027). Nothing here is slow: the server never runs a password KDF. */

const encoder = new TextEncoder();

export function base64urlEncode(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (const b of view) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64urlDecode(text: string): Uint8Array<ArrayBuffer> | null {
  if (!/^[A-Za-z0-9_-]*$/.test(text)) return null;
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  try {
    const binary = atob(padded);
    const out = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

/** Accepts base64 or base64url (Worker secrets are generated as base64url). */
export function base64Decode(text: string): Uint8Array<ArrayBuffer> | null {
  return base64urlDecode(text.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""));
}

export function randomBytes(count: number): Uint8Array<ArrayBuffer> {
  return crypto.getRandomValues(new Uint8Array(count));
}

/** Random identifier: 16 bytes, base64url (22 characters). */
export function randomId(): string {
  return base64urlEncode(randomBytes(16));
}

export async function sha256Hex(data: ArrayBuffer | Uint8Array | string): Promise<string> {
  const input = typeof data === "string" ? encoder.encode(data) : data;
  const digest = await crypto.subtle.digest("SHA-256", input);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function hmacSha256(
  key: Uint8Array<ArrayBuffer>,
  message: string,
): Promise<Uint8Array<ArrayBuffer>> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, encoder.encode(message)));
}

/** HMAC keyed with a Worker secret (base64 or base64url text). */
export async function hmacWithSecret(
  secret: string,
  message: string,
): Promise<Uint8Array<ArrayBuffer>> {
  return hmacSha256(secretBytes(secret), message);
}

/** Constant-time comparison of two byte arrays. */
export function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return diff === 0;
}

function secretBytes(secret: string): Uint8Array<ArrayBuffer> {
  const raw = base64Decode(secret);
  if (!raw || raw.length < 32) throw new Error("Worker secret must be at least 32 bytes");
  return raw;
}

async function aesKey(encodedKey: string): Promise<CryptoKey> {
  const raw = secretBytes(encodedKey);
  if (raw.length !== 32) throw new Error("DEVICE_ENC_KEY must be 32 bytes");
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

/** Encrypts a device secret at rest (AES-256-GCM, random 96-bit IV). */
export async function encryptSecret(
  encodedKey: string,
  secret: Uint8Array<ArrayBuffer>,
): Promise<{ ciphertext: Uint8Array; iv: Uint8Array }> {
  const iv = randomBytes(12);
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await aesKey(encodedKey),
    secret,
  );
  return { ciphertext: new Uint8Array(ciphertext), iv };
}

export async function decryptSecret(
  encodedKey: string,
  ciphertext: Uint8Array<ArrayBuffer>,
  iv: Uint8Array<ArrayBuffer>,
): Promise<Uint8Array<ArrayBuffer>> {
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    await aesKey(encodedKey),
    ciphertext,
  );
  return new Uint8Array(plain);
}
