import type { MiddlewareHandler } from "hono";
import { ApiError } from "./errors";
import { hmacWithSecret, base64urlEncode } from "./crypto";

/**
 * Free-tier guards (ADR-027 §11). Every number here is part of the budget documented in the ADR;
 * change both together.
 */
export const LIMITS = {
  /** JSON request bodies. */
  jsonBodyBytes: 64 * 1024,
  /** One encrypted backup chunk (D1 rows max out at 2 MB). */
  backupChunkBytes: 512 * 1024,
  /** One dish photo stored in KV (the admin panel resizes to ≤ 200 KB). */
  photoBytes: 256 * 1000,
  /** KV writes we allow per day out of the free 1,000. */
  kvWritesPerDay: 500,
  /** Admin lists. */
  pageSize: 50,
  /** `last_seen_at` is written at most this often per device. */
  lastSeenEveryMs: 60 * 60 * 1000,
} as const;

/** Rejects bodies larger than `maxBytes` with 413 before they're read into memory. */
export function bodyLimit(maxBytes: number): MiddlewareHandler {
  return async (c, next) => {
    if (c.req.method === "GET" || c.req.method === "HEAD") return next();
    const declared = Number(c.req.header("Content-Length") ?? "NaN");
    if (Number.isFinite(declared) && declared > maxBytes) {
      throw new ApiError("payload_too_large", 413, { maxBytes });
    }
    const body = await c.req.arrayBuffer();
    if (body.byteLength > maxBytes) throw new ApiError("payload_too_large", 413, { maxBytes });
    await next();
  };
}

export function clientIp(header: string | undefined): string {
  return header?.trim() || "unknown";
}

/** IPs are never stored in clear: a keyed hash, truncated (ADR-027 §6). */
export async function ipHash(secret: string, ip: string): Promise<string> {
  return base64urlEncode((await hmacWithSecret(secret, `ip:${ip}`)).slice(0, 12));
}

/** Workers Rate Limiting binding check. */
export async function limit(limiter: RateLimit, key: string): Promise<void> {
  const { success } = await limiter.limit({ key });
  if (!success) throw new ApiError("rate_limited", 429);
}

/** Per-IP limit on a route group, using the given binding. */
export function ipRateLimit(pick: (env: Env) => RateLimit): MiddlewareHandler<{ Bindings: Env }> {
  return async (c, next) => {
    await limit(pick(c.env), `ip:${clientIp(c.req.header("CF-Connecting-IP"))}`);
    await next();
  };
}
