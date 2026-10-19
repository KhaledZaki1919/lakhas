import { Hono } from "hono";
import { z } from "zod";
import {
  audit,
  devicesOf,
  revokeAllDevicesStatements,
  revokeDeviceStatements,
  userById,
} from "../db/accounts";
import { randomBytes } from "../lib/crypto";
import { ApiError } from "../lib/errors";
import { LIMITS } from "../lib/limits";
import { body } from "../lib/validate";
import { usageToday } from "../services/quota";
import type { AdminEnv } from "../types";

/** JSON API behind the admin panel (ADR-027 §1, §7). Every change is audited. */
export const adminApi = new Hono<AdminEnv>();

/** CSRF: changes need our custom header, and a same-origin Origin when the browser sends one. */
adminApi.use("*", async (c, next) => {
  if (c.req.method !== "GET" && c.req.method !== "HEAD") {
    const origin = c.req.header("Origin");
    if (
      c.req.header("X-Lakhas-Admin") !== "1" ||
      (origin && origin !== new URL(c.req.url).origin)
    ) {
      throw new ApiError("forbidden", 403);
    }
  }
  await next();
});

adminApi.get("/overview", async (c) => {
  const db = c.env.DB;
  const counts = await db
    .prepare(
      `SELECT
         (SELECT COUNT(*) FROM users) AS users,
         (SELECT COUNT(*) FROM users WHERE status = 'disabled') AS disabled,
         (SELECT COUNT(*) FROM devices WHERE status = 'active') AS devices`,
    )
    .run<{ users: number; disabled: number; devices: number }>();
  const invite = await db
    .prepare(
      "SELECT code, max_uses, uses, expires_at FROM invites WHERE active = 1 ORDER BY created_at DESC LIMIT 1",
    )
    .first();
  return c.json({
    ...counts.results[0],
    invite,
    storage: { mainDbBytes: counts.meta.size_after ?? null },
    today: {
      kvWrites: await usageToday(db, "kv_writes"),
      kvWritesLimit: LIMITS.kvWritesPerDay,
    },
  });
});

adminApi.get("/users", async (c) => {
  const query = (c.req.query("q") ?? "").trim().toLowerCase();
  const before = Number(c.req.query("before") ?? Number.MAX_SAFE_INTEGER);
  const rows = await c.env.DB.prepare(
    `SELECT u.id, u.email, u.status, u.created_at, u.share_products, u.locked_until,
            (SELECT COUNT(*) FROM devices d WHERE d.user_id = u.id AND d.status = 'active') AS devices,
            (SELECT MAX(last_seen_at) FROM devices d WHERE d.user_id = u.id) AS last_seen_at
     FROM users u
     WHERE u.created_at < ? AND (? = '' OR u.email LIKE ? ESCAPE '\\')
     ORDER BY u.created_at DESC LIMIT ?`,
  )
    .bind(before, query, `${query.replace(/[\\%_]/g, (m) => `\\${m}`)}%`, LIMITS.pageSize)
    .all();
  return c.json({ users: rows.results });
});

adminApi.get("/users/:id", async (c) => {
  const user = await userById(c.env.DB, c.req.param("id"));
  if (!user) throw new ApiError("not_found", 404);
  const devices = await devicesOf(c.env.DB, user.id);
  return c.json({ user, devices: devices.results });
});

/** Disable (every token stops working at once) or re-enable a user. */
adminApi.post("/users/:id/status", async (c) => {
  const input = await body(c, z.object({ status: z.enum(["active", "disabled"]) }));
  const db = c.env.DB;
  const id = c.req.param("id");
  const now = Date.now();
  const updated = await db
    .prepare("UPDATE users SET status = ?, updated_at = ? WHERE id = ?")
    .bind(input.status, now, id)
    .run();
  if (updated.meta.changes === 0) throw new ApiError("not_found", 404);
  await db.batch([
    ...(input.status === "disabled" ? revokeAllDevicesStatements(db, id, now) : []),
    audit(
      db,
      c.var.adminEmail,
      input.status === "disabled" ? "user_disabled" : "user_enabled",
      id,
      now,
    ),
  ]);
  return c.json({ ok: true });
});

adminApi.post("/devices/:id/revoke", async (c) => {
  const db = c.env.DB;
  const id = c.req.param("id");
  const now = Date.now();
  const exists = await db.prepare("SELECT id FROM devices WHERE id = ?").bind(id).first();
  if (!exists) throw new ApiError("not_found", 404);
  await db.batch([
    ...revokeDeviceStatements(db, id, now),
    audit(db, c.var.adminEmail, "device_revoked", id, now),
  ]);
  return c.json({ ok: true });
});

adminApi.get("/invites", async (c) => {
  const rows = await c.env.DB.prepare(
    "SELECT code, active, max_uses, uses, expires_at, created_at FROM invites ORDER BY created_at DESC LIMIT ?",
  )
    .bind(LIMITS.pageSize)
    .all();
  return c.json({ invites: rows.results });
});

/** A new invite code (mine or a random one). Older codes stop working. */
adminApi.post("/invites", async (c) => {
  const input = await body(
    c,
    z.object({
      code: z
        .string()
        .trim()
        .toUpperCase()
        .regex(/^[A-Z0-9-]{6,40}$/)
        .optional(),
      maxUses: z.number().int().min(1).max(10_000).optional(),
      expiresInDays: z.number().int().min(1).max(365).optional(),
    }),
  );
  const db = c.env.DB;
  const now = Date.now();
  const code = input.code ?? randomInviteCode();
  const expiresAt = input.expiresInDays ? now + input.expiresInDays * 24 * 60 * 60 * 1000 : null;
  const taken = await db.prepare("SELECT code FROM invites WHERE code = ?").bind(code).first();
  if (taken) throw new ApiError("invalid_request", 400, { reason: "code_used_before" });
  await db.batch([
    db.prepare("UPDATE invites SET active = 0 WHERE active = 1"),
    db
      .prepare(
        "INSERT INTO invites (code, active, max_uses, uses, expires_at, created_at) VALUES (?, 1, ?, 0, ?, ?)",
      )
      .bind(code, input.maxUses ?? null, expiresAt, now),
    audit(db, c.var.adminEmail, "invite_created", null, now),
  ]);
  return c.json({ code, maxUses: input.maxUses ?? null, expiresAt }, 201);
});

adminApi.post("/invites/deactivate", async (c) => {
  const db = c.env.DB;
  const now = Date.now();
  await db.batch([
    db.prepare("UPDATE invites SET active = 0 WHERE active = 1"),
    audit(db, c.var.adminEmail, "invites_deactivated", null, now),
  ]);
  return c.json({ ok: true });
});

adminApi.get("/audit", async (c) => {
  const before = Number(c.req.query("before") ?? Number.MAX_SAFE_INTEGER);
  const rows = await c.env.DB.prepare(
    "SELECT id, actor, action, target, created_at FROM admin_audit WHERE id < ? ORDER BY id DESC LIMIT ?",
  )
    .bind(before, LIMITS.pageSize)
    .all();
  return c.json({ entries: rows.results });
});

adminApi.get("/abuse", async (c) => {
  const rows = await c.env.DB.prepare(
    "SELECT id, kind, ip_hash, user_id, created_at FROM abuse_events ORDER BY id DESC LIMIT ?",
  )
    .bind(LIMITS.pageSize)
    .all();
  return c.json({ events: rows.results });
});

const INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // no 0/O, 1/I/L

/** "XXXX-XXXX-XXXX" from an unambiguous alphabet (~59 bits). */
export function randomInviteCode(): string {
  const chars: string[] = [];
  while (chars.length < 12) {
    for (const byte of randomBytes(16)) {
      // Rejection sampling keeps every character equally likely.
      if (byte < 248 && chars.length < 12) chars.push(INVITE_ALPHABET.charAt(byte % 31));
    }
  }
  return [chars.slice(0, 4), chars.slice(4, 8), chars.slice(8, 12)]
    .map((g) => g.join(""))
    .join("-");
}
