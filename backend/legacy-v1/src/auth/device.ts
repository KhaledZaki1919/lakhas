import type { MiddlewareHandler } from "hono";
import { getDevice, markSeen } from "../db/devices";
import { ApiError, langOf } from "../lib/errors";
import { base64urlDecode, decryptSecret, timingSafeEqual } from "../lib/crypto";
import { log } from "../lib/log";
import type { AppEnv } from "../types";
import { sign } from "./signing";

export const MAX_SKEW_MS = 5 * 60 * 1000;
const TOKEN_ID_RE = /^[A-Za-z0-9]{12,32}$/;
const TIMESTAMP_RE = /^\d{13}$/;
const NONCE_RE = /^[A-Za-z0-9_-]{22}$/; // 16 bytes, base64url

/**
 * Verifies the HMAC-signed device token on every /v1 request (ADR-013):
 * headers present → timestamp fresh → token active → signature valid → nonce unused.
 * The nonce is recorded only after the signature checks out, so strangers can't burn nonces.
 */
export const deviceAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const tokenId = c.req.header("X-Lakhas-Token-Id") ?? "";
  const timestamp = c.req.header("X-Lakhas-Timestamp") ?? "";
  const nonce = c.req.header("X-Lakhas-Nonce") ?? "";
  const signature = base64urlDecode(c.req.header("X-Lakhas-Signature") ?? "");

  if (!TOKEN_ID_RE.test(tokenId) || !TIMESTAMP_RE.test(timestamp) || !NONCE_RE.test(nonce)) {
    throw new ApiError("unauthorized", 401);
  }
  if (!signature || signature.length !== 32) throw new ApiError("bad_signature", 401);

  const now = Date.now();
  if (Math.abs(now - Number(timestamp)) > MAX_SKEW_MS) {
    throw new ApiError("stale_request", 401, { serverTime: new Date(now).toISOString() });
  }

  const device = await getDevice(c.env.DB, tokenId);
  if (!device) throw new ApiError("unauthorized", 401);
  if (device.status === "revoked" || !device.secret_enc || !device.secret_iv) {
    throw new ApiError("token_revoked", 401);
  }

  const ciphertext = base64urlDecode(device.secret_enc);
  const iv = base64urlDecode(device.secret_iv);
  if (!ciphertext || !iv) throw new ApiError("internal", 500);
  const secret = await decryptSecret(c.env.TOKEN_ENC_KEY, ciphertext, iv);

  const url = new URL(c.req.url);
  const expected = base64urlDecode(
    await sign(secret, {
      method: c.req.method,
      pathAndQuery: url.pathname + url.search,
      timestamp,
      nonce,
      body: await c.req.arrayBuffer(),
    }),
  );
  if (!expected || !timingSafeEqual(signature, expected)) {
    log("warn", "bad_signature", { device: tokenId.slice(0, 4) });
    throw new ApiError("bad_signature", 401);
  }

  const inserted = await c.env.DB.prepare(
    "INSERT INTO request_nonces (token_id, nonce, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
  )
    .bind(tokenId, nonce, now)
    .run();
  if (inserted.meta.changes === 0) throw new ApiError("replayed_request", 401);

  c.set("device", device);
  c.executionCtx.waitUntil(markSeen(c.env.DB, tokenId, now, langOf(c)));
  await next();
};

/** Per-IP burst limit (Workers Rate Limiting binding). */
export const ipRateLimit: MiddlewareHandler<AppEnv> = async (c, next) => {
  const ip = c.req.header("CF-Connecting-IP") ?? "unknown";
  const { success } = await c.env.IP_LIMITER.limit({ key: ip });
  if (!success) throw new ApiError("rate_limited", 429);
  await next();
};
