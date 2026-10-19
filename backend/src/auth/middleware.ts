import type { MiddlewareHandler } from "hono";
import { deviceWithUser } from "../db/accounts";
import { base64urlDecode, decryptSecret, timingSafeEqual } from "../lib/crypto";
import { ApiError } from "../lib/errors";
import { LIMITS, limit } from "../lib/limits";
import { log } from "../lib/log";
import type { ApiEnv } from "../types";
import { sign } from "./signing";
import { readAccessToken } from "./tokens";

export const MAX_SKEW_MS = 5 * 60 * 1000;
const ID_RE = /^[A-Za-z0-9_-]{22}$/; // 16 bytes, base64url
const TIMESTAMP_RE = /^\d{13}$/;
const NONCE_RE = /^[A-Za-z0-9_-]{22}$/; // 16 bytes, base64url

/**
 * LK2 request signature (ADR-027 §1): headers present → per-device rate limit → timestamp fresh →
 * device active and its user active → signature valid → nonce unused. The nonce is stored only
 * after the signature checks out, so strangers can't burn nonces or D1 writes.
 */
export const signedDevice: MiddlewareHandler<ApiEnv> = async (c, next) => {
  const deviceId = c.req.header("X-Lakhas-Device") ?? "";
  const timestamp = c.req.header("X-Lakhas-Timestamp") ?? "";
  const nonce = c.req.header("X-Lakhas-Nonce") ?? "";
  const signature = base64urlDecode(c.req.header("X-Lakhas-Signature") ?? "");

  if (!ID_RE.test(deviceId) || !TIMESTAMP_RE.test(timestamp) || !NONCE_RE.test(nonce)) {
    throw new ApiError("unauthorized", 401);
  }
  if (!signature || signature.length !== 32) throw new ApiError("bad_signature", 401);
  await limit(c.env.DEVICE_LIMITER, `device:${deviceId}`);

  const now = Date.now();
  if (Math.abs(now - Number(timestamp)) > MAX_SKEW_MS) {
    throw new ApiError("stale_request", 401, { serverTime: now });
  }

  const device = await deviceWithUser(c.env.DB, deviceId);
  if (!device) throw new ApiError("unauthorized", 401);
  if (device.status !== "active" || !device.secret_enc || !device.secret_iv) {
    throw new ApiError("device_revoked", 401);
  }
  if (device.user_status !== "active") throw new ApiError("account_disabled", 403);

  const ciphertext = base64urlDecode(device.secret_enc);
  const iv = base64urlDecode(device.secret_iv);
  if (!ciphertext || !iv) throw new ApiError("internal", 500);
  const secret = await decryptSecret(c.env.DEVICE_ENC_KEY, ciphertext, iv);

  const url = new URL(c.req.url);
  const expected = base64urlDecode(
    await sign(secret, {
      method: c.req.method,
      pathAndQuery: url.pathname + url.search,
      timestamp,
      nonce,
      deviceId,
      body: await c.req.arrayBuffer(),
    }),
  );
  if (!expected || !timingSafeEqual(signature, expected)) {
    log("warn", "bad_signature", { path: url.pathname });
    throw new ApiError("bad_signature", 401);
  }

  const inserted = await c.env.DB.prepare(
    "INSERT INTO request_nonces (device_id, nonce, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
  )
    .bind(deviceId, nonce, now)
    .run();
  if (inserted.meta.changes === 0) throw new ApiError("replayed_request", 401);

  c.set("device", device);
  if (!device.last_seen_at || now - device.last_seen_at > LIMITS.lastSeenEveryMs) {
    c.executionCtx.waitUntil(
      c.env.DB.prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?")
        .bind(now, deviceId)
        .run(),
    );
  }
  await next();
};

/**
 * Signed request + a valid access token for the same device. An expired token answers
 * `session_expired`, and the phone refreshes and retries.
 */
export const session: MiddlewareHandler<ApiEnv> = async (c, next) => {
  const header = c.req.header("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) throw new ApiError("unauthorized", 401);
  const claims = await readAccessToken(c.env.ACCESS_TOKEN_KEY, token);
  if (!claims || claims.d !== c.req.header("X-Lakhas-Device")) {
    throw new ApiError("unauthorized", 401);
  }
  if (claims.exp <= Date.now()) throw new ApiError("session_expired", 401);
  await signedDevice(c, async () => {
    if (c.var.device.user_id !== claims.u) throw new ApiError("unauthorized", 401);
    await next();
  });
};
