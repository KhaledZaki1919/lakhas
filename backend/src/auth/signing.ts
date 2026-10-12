import { base64urlDecode, base64urlEncode, hmacSha256, sha256Hex } from "../lib/crypto";

/** Device token format (ADR-013): `lk1_<tokenId>_<secret>`, secret = 32 bytes base64url. */
export const TOKEN_PREFIX = "lk1";
const TOKEN_RE = /^lk1_([A-Za-z0-9]{12,32})_([A-Za-z0-9_-]{43})$/;

export function parseToken(
  token: string,
): { tokenId: string; secret: Uint8Array<ArrayBuffer> } | null {
  const match = TOKEN_RE.exec(token.trim());
  if (!match?.[1] || !match[2]) return null;
  const secret = base64urlDecode(match[2]);
  if (!secret || secret.length !== 32) return null;
  return { tokenId: match[1], secret };
}

export function formatToken(tokenId: string, secret: Uint8Array): string {
  return `${TOKEN_PREFIX}_${tokenId}_${base64urlEncode(secret)}`;
}

/**
 * The exact string both sides sign:
 * "LK1\n" + METHOD + "\n" + path[?query] + "\n" + timestamp + "\n" + nonce + "\n" + hex(SHA256(body))
 * Test vectors: shared/test-vectors/signing.json (used by the Swift tests too).
 */
export async function canonicalString(input: {
  method: string;
  pathAndQuery: string;
  timestamp: string;
  nonce: string;
  body: ArrayBuffer | Uint8Array | string;
}): Promise<string> {
  const bodyHash = await sha256Hex(input.body);
  return [
    "LK1",
    input.method.toUpperCase(),
    input.pathAndQuery,
    input.timestamp,
    input.nonce,
    bodyHash,
  ].join("\n");
}

export async function sign(
  secret: Uint8Array<ArrayBuffer>,
  input: Parameters<typeof canonicalString>[0],
): Promise<string> {
  return base64urlEncode(await hmacSha256(secret, await canonicalString(input)));
}
