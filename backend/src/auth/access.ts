import type { MiddlewareHandler } from "hono";
import { ApiError } from "../lib/errors";
import { base64urlDecode } from "../lib/crypto";
import type { AdminEnv } from "../types";

/**
 * Verifies the Cloudflare Access JWT on every admin Worker request (ADR-027 §7) as defense in depth:
 * Access already blocks unauthenticated requests at the edge, and the Worker checks
 * the signature, audience, issuer and expiry itself.
 */
interface Jwk extends JsonWebKey {
  kid?: string;
}
interface Jwks {
  keys: Jwk[];
}

const decoder = new TextDecoder();
let cachedJwks: { domain: string; jwks: Jwks; fetchedAt: number } | null = null;
const JWKS_TTL_MS = 60 * 60 * 1000;

async function loadJwks(env: Env): Promise<Jwks> {
  if (env.ENVIRONMENT === "test" && env.ACCESS_TEST_JWKS) {
    return JSON.parse(env.ACCESS_TEST_JWKS) as Jwks;
  }
  const domain = env.ACCESS_TEAM_DOMAIN;
  if (
    cachedJwks &&
    cachedJwks.domain === domain &&
    Date.now() - cachedJwks.fetchedAt < JWKS_TTL_MS
  ) {
    return cachedJwks.jwks;
  }
  const res = await fetch(`https://${domain}/cdn-cgi/access/certs`);
  if (!res.ok) throw new ApiError("unauthorized", 401);
  const jwks = (await res.json()) as Jwks;
  cachedJwks = { domain, jwks, fetchedAt: Date.now() };
  return jwks;
}

function decodeSegment(segment: string | undefined): Record<string, unknown> | null {
  const bytes = segment ? base64urlDecode(segment) : null;
  if (!bytes) return null;
  try {
    return JSON.parse(decoder.decode(bytes)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export async function verifyAccessJwt(token: string, env: Env): Promise<string> {
  const [headerB64, payloadB64, signatureB64] = token.split(".");
  const header = decodeSegment(headerB64);
  const payload = decodeSegment(payloadB64);
  const signature = signatureB64 ? base64urlDecode(signatureB64) : null;
  if (!header || !payload || !signature || header.alg !== "RS256") {
    throw new ApiError("unauthorized", 401);
  }

  const jwk = (await loadJwks(env)).keys.find((k) => k.kid === header.kid);
  if (!jwk) throw new ApiError("unauthorized", 401);
  const key = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    signature,
    new TextEncoder().encode(`${headerB64}.${payloadB64}`),
  );
  if (!valid) throw new ApiError("unauthorized", 401);

  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  const now = Date.now() / 1000;
  if (
    !audiences.includes(env.ACCESS_AUD) ||
    payload.iss !== `https://${env.ACCESS_TEAM_DOMAIN}` ||
    typeof payload.exp !== "number" ||
    payload.exp < now ||
    typeof payload.email !== "string"
  ) {
    throw new ApiError("unauthorized", 401);
  }
  return payload.email;
}

export const accessAuth: MiddlewareHandler<AdminEnv> = async (c, next) => {
  const token = c.req.header("Cf-Access-Jwt-Assertion");
  if (!token) throw new ApiError("unauthorized", 401);
  c.set("adminEmail", await verifyAccessJwt(token, c.env));
  await next();
};
