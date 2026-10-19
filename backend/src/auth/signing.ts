import { base64urlEncode, hmacSha256, sha256Hex } from "../lib/crypto";

/**
 * Request signing, version LK2 (ADR-027 §1, revived from ADR-013). Both sides sign:
 *
 *   "LK2\n" + METHOD + "\n" + path[?query] + "\n" + timestamp + "\n" + nonce + "\n" + deviceId
 *   + "\n" + hex(SHA256(body))
 *
 * with the device's 32-byte secret (HMAC-SHA256, base64url). Test vectors:
 * shared/test-vectors/signing.json (used by the Swift tests too).
 */
export const SIGNING_VERSION = "LK2";

export interface SigningInput {
  method: string;
  pathAndQuery: string;
  timestamp: string;
  nonce: string;
  deviceId: string;
  body: ArrayBuffer | Uint8Array | string;
}

export async function canonicalString(input: SigningInput): Promise<string> {
  return [
    SIGNING_VERSION,
    input.method.toUpperCase(),
    input.pathAndQuery,
    input.timestamp,
    input.nonce,
    input.deviceId,
    await sha256Hex(input.body),
  ].join("\n");
}

export async function sign(secret: Uint8Array<ArrayBuffer>, input: SigningInput): Promise<string> {
  return base64urlEncode(await hmacSha256(secret, await canonicalString(input)));
}
