import { Hono } from "hono";
import { z } from "zod";
import {
  KDF_MIN_ITERATIONS,
  KDF_NAME,
  decoySalt,
  deviceInfo,
  email,
  envelope,
  kdfParams,
  key32,
  lockoutUntil,
  matchesVerifier,
  recoveryMaterial,
  salts,
  verifierFor,
} from "../auth/credentials";
import { session, signedDevice } from "../auth/middleware";
import { hashToken } from "../auth/tokens";
import {
  audit,
  credentialFor,
  envelopeFor,
  putEnvelope,
  recoveryFor,
  revokeAllDevicesStatements,
  revokeDeviceStatements,
  userByEmail,
  userById,
  type UserRow,
} from "../db/accounts";
import { base64urlEncode, randomBytes, randomId } from "../lib/crypto";
import { ApiError } from "../lib/errors";
import { clientIp, ipHash, ipRateLimit } from "../lib/limits";
import { body } from "../lib/validate";
import { prepareSession, prepareTokens } from "../services/sessions";
import type { ApiEnv } from "../types";

const RECOVERY_TICKET_TTL_MS = 10 * 60 * 1000;

const signupSchema = z.object({
  inviteCode: z.string().trim().toUpperCase().min(4).max(40),
  email,
  authKey: key32,
  kdf: kdfParams,
  salts,
  recovery: recoveryMaterial,
  envelopes: z.object({ password: envelope, recovery: envelope }),
  device: deviceInfo,
});

const loginSchema = z.object({ email, authKey: key32, device: deviceInfo });

const newPasswordSchema = z.object({ authKey: key32, kdf: kdfParams, salts, envelope });

/** Public auth routes (strict per-IP limit) plus the signed refresh / sign-out / password routes. */
export const auth = new Hono<ApiEnv>();

const open = new Hono<ApiEnv>();
open.use(
  "*",
  ipRateLimit((env) => env.AUTH_LIMITER),
);

open.post("/prelogin", async (c) => {
  const { email: address } = await body(c, z.object({ email }));
  const user = await userByEmail(c.env.DB, address);
  const credential = user ? await credentialFor(c.env.DB, user.id) : null;
  const recovery = user ? await recoveryFor(c.env.DB, user.id) : null;
  const pepper = c.env.PEPPER;
  return c.json({
    kdf: {
      name: credential?.kdf ?? KDF_NAME,
      iterations: credential?.iterations ?? KDF_MIN_ITERATIONS,
    },
    salts: {
      kdf: credential?.kdf_salt ?? (await decoySalt(pepper, "kdf", address)),
      auth: credential?.auth_salt ?? (await decoySalt(pepper, "auth", address)),
      enc: credential?.enc_salt ?? (await decoySalt(pepper, "enc", address)),
    },
    recoverySalt: recovery?.salt ?? (await decoySalt(pepper, "recovery", address)),
  });
});

open.post("/signup", async (c) => {
  const input = await body(c, signupSchema);
  const db = c.env.DB;
  const now = Date.now();
  if (await userByEmail(db, input.email)) throw new ApiError("email_taken", 409);

  const invite = await db
    .prepare(
      `UPDATE invites SET uses = uses + 1
       WHERE code = ? AND active = 1 AND (expires_at IS NULL OR expires_at > ?)
         AND (max_uses IS NULL OR uses < max_uses)
       RETURNING code`,
    )
    .bind(input.inviteCode, now)
    .first<{ code: string }>();
  if (!invite) {
    await recordAbuse(c.env, "invalid_invite", c.req.header("CF-Connecting-IP"), now);
    throw new ApiError("invalid_invite", 403);
  }

  const userId = randomId();
  const { statements, session: newSession } = await prepareSession(
    c.env,
    userId,
    input.device,
    now,
  );
  try {
    await db.batch([
      db
        .prepare(
          `INSERT INTO users (id, email, status, share_products, invite_code, created_at, updated_at)
           VALUES (?, ?, 'active', 1, ?, ?, ?)`,
        )
        .bind(userId, input.email, invite.code, now, now),
      db
        .prepare(
          "INSERT INTO identities (provider, subject, user_id, email, created_at) VALUES ('password', ?, ?, ?, ?)",
        )
        .bind(userId, userId, input.email, now),
      db
        .prepare(
          `INSERT INTO password_credentials
             (user_id, kdf, iterations, kdf_salt, auth_salt, enc_salt, verifier, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        )
        .bind(
          userId,
          input.kdf.name,
          input.kdf.iterations,
          input.salts.kdf,
          input.salts.auth,
          input.salts.enc,
          await verifierFor(c.env.PEPPER, "auth", input.authKey),
          now,
        ),
      db
        .prepare(
          "INSERT INTO recovery_credentials (user_id, salt, verifier, updated_at) VALUES (?, ?, ?, ?)",
        )
        .bind(
          userId,
          input.recovery.salt,
          await verifierFor(c.env.PEPPER, "recovery", input.recovery.authKey),
          now,
        ),
      putEnvelope(db, userId, "password", input.envelopes.password, now),
      putEnvelope(db, userId, "recovery", input.envelopes.recovery, now),
      ...statements,
      audit(db, "user", "signup", userId, now),
    ]);
  } catch (err) {
    // Lost a race for the same email: give the invite use back.
    await db.prepare("UPDATE invites SET uses = uses - 1 WHERE code = ?").bind(invite.code).run();
    if (await userByEmail(db, input.email)) throw new ApiError("email_taken", 409);
    throw err;
  }
  return c.json({ user: { id: userId, email: input.email }, session: newSession }, 201);
});

open.post("/login", async (c) => {
  const input = await body(c, loginSchema);
  const db = c.env.DB;
  const now = Date.now();
  const user = await userByEmail(db, input.email);
  if (!user) {
    // Same work as a real check, so timing doesn't reveal unknown emails.
    await verifierFor(c.env.PEPPER, "auth", input.authKey);
    throw new ApiError("invalid_credentials", 401);
  }
  assertNotLocked(user.locked_until, now);
  const credential = await credentialFor(db, user.id);
  if (
    !credential ||
    !(await matchesVerifier(c.env.PEPPER, "auth", input.authKey, credential.verifier))
  ) {
    await recordFailedLogin(c.env, user, now, c.req.header("CF-Connecting-IP"));
    throw new ApiError("invalid_credentials", 401);
  }
  if (user.status !== "active") throw new ApiError("account_disabled", 403);

  const passwordEnvelope = await envelopeFor(db, user.id, "password");
  const { statements, session: newSession } = await prepareSession(
    c.env,
    user.id,
    input.device,
    now,
  );
  await db.batch([
    db
      .prepare(
        "UPDATE users SET failed_logins = 0, locked_until = NULL, updated_at = ? WHERE id = ?",
      )
      .bind(now, user.id),
    ...statements,
  ]);
  return c.json({
    user: { id: user.id, email: user.email },
    session: newSession,
    keys: {
      envelope: passwordEnvelope && {
        nonce: passwordEnvelope.nonce,
        wrapped: passwordEnvelope.wrapped,
      },
    },
  });
});

/** Step 1 of a reset with the recovery code: prove it, get the recovery-wrapped key + a ticket. */
open.post("/recovery/start", async (c) => {
  const input = await body(c, z.object({ email, recoveryAuth: key32 }));
  const db = c.env.DB;
  const now = Date.now();
  const user = await userByEmail(db, input.email);
  const recovery = user ? await recoveryFor(db, user.id) : null;
  if (!user || !recovery) {
    await verifierFor(c.env.PEPPER, "recovery", input.recoveryAuth);
    throw new ApiError("invalid_credentials", 401);
  }
  assertNotLocked(recovery.locked_until, now);
  if (!(await matchesVerifier(c.env.PEPPER, "recovery", input.recoveryAuth, recovery.verifier))) {
    const failures = recovery.failed_attempts + 1;
    await db
      .prepare(
        "UPDATE recovery_credentials SET failed_attempts = ?, locked_until = ? WHERE user_id = ?",
      )
      .bind(failures, lockoutUntil(failures, now), user.id)
      .run();
    await recordAbuse(c.env, "bad_recovery_code", c.req.header("CF-Connecting-IP"), now, user.id);
    throw new ApiError("invalid_credentials", 401);
  }
  if (user.status !== "active") throw new ApiError("account_disabled", 403);

  const recoveryEnvelope = await envelopeFor(db, user.id, "recovery");
  const ticket = base64urlEncode(randomBytes(32));
  await db.batch([
    db
      .prepare(
        "UPDATE recovery_credentials SET failed_attempts = 0, locked_until = NULL WHERE user_id = ?",
      )
      .bind(user.id),
    db
      .prepare("INSERT INTO recovery_tickets (ticket_hash, user_id, expires_at) VALUES (?, ?, ?)")
      .bind(await hashToken(ticket), user.id, now + RECOVERY_TICKET_TTL_MS),
  ]);
  return c.json({
    ticket,
    ticketExpiresAt: now + RECOVERY_TICKET_TTL_MS,
    envelope: recoveryEnvelope && {
      nonce: recoveryEnvelope.nonce,
      wrapped: recoveryEnvelope.wrapped,
    },
  });
});

/** Step 2: a new password (key re-wrapped on the phone). Every other session is signed out. */
open.post("/recovery/reset", async (c) => {
  const input = await body(
    c,
    newPasswordSchema.extend({ ticket: z.string().min(40).max(60), device: deviceInfo }),
  );
  const db = c.env.DB;
  const now = Date.now();
  const ticketHash = await hashToken(input.ticket);
  const claimed = await db
    .prepare(
      `UPDATE recovery_tickets SET used_at = ?
       WHERE ticket_hash = ? AND used_at IS NULL AND expires_at > ? RETURNING user_id`,
    )
    .bind(now, ticketHash, now)
    .first<{ user_id: string }>();
  const user = claimed ? await userById(db, claimed.user_id) : null;
  if (!user) throw new ApiError("unauthorized", 401);
  if (user.status !== "active") throw new ApiError("account_disabled", 403);

  const { statements, session: newSession } = await prepareSession(
    c.env,
    user.id,
    input.device,
    now,
  );
  await db.batch([
    ...(await newPasswordStatements(c.env, user.id, input, now)),
    ...revokeAllDevicesStatements(db, user.id, now),
    db
      .prepare(
        "UPDATE users SET failed_logins = 0, locked_until = NULL, updated_at = ? WHERE id = ?",
      )
      .bind(now, user.id),
    ...statements,
    audit(db, "user", "password_reset_with_recovery_code", user.id, now),
  ]);
  return c.json({ user: { id: user.id, email: user.email }, session: newSession });
});

auth.route("/", open);

/** Signed, no access token needed: rotates the refresh token. Reusing an old one signs the device out. */
auth.post("/refresh", signedDevice, async (c) => {
  const input = await body(
    c,
    z.object({ refreshToken: z.string().regex(/^rt_[A-Za-z0-9_-]{43}$/) }),
  );
  const db = c.env.DB;
  const device = c.var.device;
  const now = Date.now();
  const tokenHash = await hashToken(input.refreshToken);
  const row = await db
    .prepare("SELECT device_id, expires_at, used_at FROM refresh_tokens WHERE token_hash = ?")
    .bind(tokenHash)
    .first<{ device_id: string; expires_at: number; used_at: number | null }>();
  if (!row || row.device_id !== device.id) throw new ApiError("unauthorized", 401);
  const claimed = await db
    .prepare("UPDATE refresh_tokens SET used_at = ? WHERE token_hash = ? AND used_at IS NULL")
    .bind(now, tokenHash)
    .run();
  if (row.used_at !== null || claimed.meta.changes === 0) {
    // A refresh token used twice means it leaked (or the phone raced itself): sign the device out.
    await db.batch([
      ...revokeDeviceStatements(db, device.id, now),
      audit(db, "system", "refresh_token_reused", device.id, now),
    ]);
    throw new ApiError("device_revoked", 401);
  }
  if (row.expires_at <= now) throw new ApiError("unauthorized", 401);

  const { statements, tokens } = await prepareTokens(c.env, device.user_id, device.id, now);
  await db.batch(statements);
  return c.json(tokens);
});

auth.post("/logout", session, async (c) => {
  const db = c.env.DB;
  await db.batch(revokeDeviceStatements(db, c.var.device.id, Date.now()));
  return c.json({ ok: true });
});

/** Change the password while signed in: proves the current one, keeps this device signed in. */
auth.post("/password", session, async (c) => {
  const input = await body(c, newPasswordSchema.extend({ currentAuthKey: key32 }));
  const db = c.env.DB;
  const device = c.var.device;
  const now = Date.now();
  const credential = await credentialFor(db, device.user_id);
  if (
    !credential ||
    !(await matchesVerifier(c.env.PEPPER, "auth", input.currentAuthKey, credential.verifier))
  ) {
    throw new ApiError("invalid_credentials", 401);
  }
  await db.batch([
    ...(await newPasswordStatements(c.env, device.user_id, input, now)),
    ...revokeAllDevicesStatements(db, device.user_id, now, device.id),
    audit(db, "user", "password_changed", device.user_id, now),
  ]);
  return c.json({ ok: true });
});

async function newPasswordStatements(
  env: Env,
  userId: string,
  input: z.infer<typeof newPasswordSchema>,
  now: number,
) {
  return [
    env.DB.prepare(
      `UPDATE password_credentials SET kdf = ?, iterations = ?, kdf_salt = ?, auth_salt = ?,
         enc_salt = ?, verifier = ?, updated_at = ? WHERE user_id = ?`,
    ).bind(
      input.kdf.name,
      input.kdf.iterations,
      input.salts.kdf,
      input.salts.auth,
      input.salts.enc,
      await verifierFor(env.PEPPER, "auth", input.authKey),
      now,
      userId,
    ),
    putEnvelope(env.DB, userId, "password", input.envelope, now),
  ];
}

function assertNotLocked(lockedUntil: number | null, now: number) {
  if (lockedUntil && lockedUntil > now) {
    throw new ApiError("too_many_attempts", 429, { retryAfterMs: lockedUntil - now });
  }
}

async function recordFailedLogin(env: Env, user: UserRow, now: number, ip: string | undefined) {
  const failures = user.failed_logins + 1;
  await env.DB.prepare("UPDATE users SET failed_logins = ?, locked_until = ? WHERE id = ?")
    .bind(failures, lockoutUntil(failures, now), user.id)
    .run();
  if (failures >= 5) await recordAbuse(env, "login_lockout", ip, now, user.id);
}

export async function recordAbuse(
  env: Env,
  kind: string,
  ip: string | undefined,
  now: number,
  userId: string | null = null,
) {
  await env.DB.prepare(
    "INSERT INTO abuse_events (kind, ip_hash, user_id, created_at) VALUES (?, ?, ?, ?)",
  )
    .bind(kind, await ipHash(env.LOG_HASH_KEY, clientIp(ip)), userId, now)
    .run();
}
