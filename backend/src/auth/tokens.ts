import {
  base64urlDecode,
  base64urlEncode,
  hmacWithSecret,
  randomBytes,
  sha256Hex,
  timingSafeEqual,
} from "../lib/crypto";

/** Access tokens: 15 minutes, stateless, HMAC-signed with ACCESS_TOKEN_KEY (ADR-027 §1). */
export const ACCESS_TTL_MS = 15 * 60 * 1000;
/** Refresh tokens: 60 days, single use (rotated), stored hashed. */
export const REFRESH_TTL_MS = 60 * 24 * 60 * 60 * 1000;

const ACCESS_PREFIX = "v1";
const decoder = new TextDecoder();

export interface AccessClaims {
  /** user id */
  u: string;
  /** device id */
  d: string;
  /** expiry, Unix ms */
  exp: number;
}

export async function mintAccessToken(key: string, claims: AccessClaims): Promise<string> {
  const payload = base64urlEncode(new TextEncoder().encode(JSON.stringify(claims)));
  const mac = await hmacWithSecret(key, `lakhas/access/${ACCESS_PREFIX}.${payload}`);
  return `${ACCESS_PREFIX}.${payload}.${base64urlEncode(mac)}`;
}

/** Returns the claims of a well-formed, correctly signed token (expiry is checked by the caller). */
export async function readAccessToken(key: string, token: string): Promise<AccessClaims | null> {
  const [prefix, payload, mac] = token.split(".");
  if (prefix !== ACCESS_PREFIX || !payload || !mac) return null;
  const given = base64urlDecode(mac);
  const expected = await hmacWithSecret(key, `lakhas/access/${ACCESS_PREFIX}.${payload}`);
  if (!given || !timingSafeEqual(given, expected)) return null;
  const bytes = base64urlDecode(payload);
  if (!bytes) return null;
  try {
    const claims = JSON.parse(decoder.decode(bytes)) as Partial<AccessClaims>;
    if (typeof claims.u !== "string" || typeof claims.d !== "string") return null;
    if (typeof claims.exp !== "number") return null;
    return { u: claims.u, d: claims.d, exp: claims.exp };
  } catch {
    return null;
  }
}

export function newRefreshToken(): string {
  return `rt_${base64urlEncode(randomBytes(32))}`;
}

export function hashToken(token: string): Promise<string> {
  return sha256Hex(token);
}
