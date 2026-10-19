import { Hono } from "hono";
import { z } from "zod";
import {
  envelope,
  key32,
  matchesVerifier,
  recoveryMaterial,
  verifierFor,
} from "../auth/credentials";
import { session } from "../auth/middleware";
import {
  audit,
  credentialFor,
  deleteUserStatements,
  devicesOf,
  putEnvelope,
  recoveryFor,
  revokeDeviceStatements,
  userById,
} from "../db/accounts";
import { ApiError } from "../lib/errors";
import { body } from "../lib/validate";
import type { ApiEnv } from "../types";

/** The signed-in user's own account (ADR-027 §1). Every route needs a session. */
export const account = new Hono<ApiEnv>();
account.use("*", session);

account.get("/", async (c) => {
  const device = c.var.device;
  const user = await userById(c.env.DB, device.user_id);
  if (!user) throw new ApiError("unauthorized", 401);
  const devices = await devicesOf(c.env.DB, user.id);
  return c.json({
    user: {
      id: user.id,
      email: user.email,
      createdAt: user.created_at,
      shareProducts: user.share_products === 1,
    },
    devices: devices.results.map((d) => ({
      id: d.id,
      label: d.label,
      platform: d.platform,
      appVersion: d.app_version,
      status: d.status,
      createdAt: d.created_at,
      lastSeenAt: d.last_seen_at,
      current: d.id === device.id,
    })),
  });
});

account.patch("/", async (c) => {
  const input = await body(c, z.object({ shareProducts: z.boolean() }));
  await c.env.DB.prepare("UPDATE users SET share_products = ?, updated_at = ? WHERE id = ?")
    .bind(input.shareProducts ? 1 : 0, Date.now(), c.var.device.user_id)
    .run();
  return c.json({ ok: true });
});

/** A new recovery code (the old one stops working). Needs the password. */
account.post("/recovery", async (c) => {
  const input = await body(c, z.object({ authKey: key32, recovery: recoveryMaterial, envelope }));
  const db = c.env.DB;
  const userId = c.var.device.user_id;
  const now = Date.now();
  await assertPassword(c.env, userId, input.authKey);
  await db.batch([
    db
      .prepare(
        `UPDATE recovery_credentials SET salt = ?, verifier = ?, failed_attempts = 0,
           locked_until = NULL, updated_at = ? WHERE user_id = ?`,
      )
      .bind(
        input.recovery.salt,
        await verifierFor(c.env.PEPPER, "recovery", input.recovery.authKey),
        now,
        userId,
      ),
    putEnvelope(db, userId, "recovery", input.envelope, now),
    audit(db, "user", "recovery_code_replaced", userId, now),
  ]);
  return c.json({ ok: true });
});

/** Sign out one of my other devices. */
account.delete("/devices/:id", async (c) => {
  const db = c.env.DB;
  const target = c.req.param("id");
  const owned = await db
    .prepare("SELECT id FROM devices WHERE id = ? AND user_id = ?")
    .bind(target, c.var.device.user_id)
    .first();
  if (!owned) throw new ApiError("not_found", 404);
  await db.batch(revokeDeviceStatements(db, target, Date.now()));
  return c.json({ ok: true });
});

/**
 * Deletes the account and everything the server holds for it (App Store 5.1.1(v)). Needs the
 * password or the recovery code. Immediate; there is no grace period.
 */
account.delete("/", async (c) => {
  const input = await body(
    c,
    z.union([z.object({ authKey: key32 }), z.object({ recoveryAuth: key32 })]),
  );
  const db = c.env.DB;
  const userId = c.var.device.user_id;
  if ("authKey" in input) {
    await assertPassword(c.env, userId, input.authKey);
  } else {
    const recovery = await recoveryFor(db, userId);
    if (
      !recovery ||
      !(await matchesVerifier(c.env.PEPPER, "recovery", input.recoveryAuth, recovery.verifier))
    ) {
      throw new ApiError("invalid_credentials", 401);
    }
  }
  const now = Date.now();
  // Backups (Phase 10) live in their own database and are deleted there as well.
  await db.batch([
    ...deleteUserStatements(db, userId),
    audit(db, "user", "account_deleted", userId, now),
  ]);
  return c.json({ ok: true });
});

async function assertPassword(env: Env, userId: string, authKey: string) {
  const credential = await credentialFor(env.DB, userId);
  if (!credential || !(await matchesVerifier(env.PEPPER, "auth", authKey, credential.verifier))) {
    throw new ApiError("invalid_credentials", 401);
  }
}
