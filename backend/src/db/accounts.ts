/** D1 access for users, credentials, envelopes and devices (migrations/0001_accounts.sql). */

export interface UserRow {
  id: string;
  email: string;
  status: "active" | "disabled";
  share_products: number;
  failed_logins: number;
  locked_until: number | null;
  created_at: number;
}

export interface CredentialRow {
  kdf: string;
  iterations: number;
  kdf_salt: string;
  auth_salt: string;
  enc_salt: string;
  verifier: string;
}

export interface RecoveryRow {
  salt: string;
  verifier: string;
  failed_attempts: number;
  locked_until: number | null;
}

export interface EnvelopeRow {
  kind: "password" | "recovery" | "passphrase";
  version: number;
  nonce: string;
  wrapped: string;
}

export interface DeviceRow {
  id: string;
  user_id: string;
  label: string;
  platform: string;
  app_version: string | null;
  secret_enc: string | null;
  secret_iv: string | null;
  status: "active" | "revoked";
  created_at: number;
  last_seen_at: number | null;
}

export interface DeviceWithUser extends DeviceRow {
  user_status: "active" | "disabled";
}

const USER_COLUMNS = "id, email, status, share_products, failed_logins, locked_until, created_at";

export function userByEmail(db: D1Database, email: string) {
  return db
    .prepare(`SELECT ${USER_COLUMNS} FROM users WHERE email = ?`)
    .bind(email)
    .first<UserRow>();
}

export function userById(db: D1Database, id: string) {
  return db.prepare(`SELECT ${USER_COLUMNS} FROM users WHERE id = ?`).bind(id).first<UserRow>();
}

export function credentialFor(db: D1Database, userId: string) {
  return db
    .prepare(
      "SELECT kdf, iterations, kdf_salt, auth_salt, enc_salt, verifier FROM password_credentials WHERE user_id = ?",
    )
    .bind(userId)
    .first<CredentialRow>();
}

export function recoveryFor(db: D1Database, userId: string) {
  return db
    .prepare(
      "SELECT salt, verifier, failed_attempts, locked_until FROM recovery_credentials WHERE user_id = ?",
    )
    .bind(userId)
    .first<RecoveryRow>();
}

export function envelopeFor(db: D1Database, userId: string, kind: EnvelopeRow["kind"]) {
  return db
    .prepare(
      "SELECT kind, version, nonce, wrapped FROM key_envelopes WHERE user_id = ? AND kind = ?",
    )
    .bind(userId, kind)
    .first<EnvelopeRow>();
}

export function putEnvelope(
  db: D1Database,
  userId: string,
  kind: EnvelopeRow["kind"],
  value: { nonce: string; wrapped: string },
  now: number,
) {
  return db
    .prepare(
      `INSERT INTO key_envelopes (user_id, kind, version, nonce, wrapped, updated_at)
       VALUES (?, ?, 1, ?, ?, ?)
       ON CONFLICT (user_id, kind) DO UPDATE SET
         version = version + 1, nonce = excluded.nonce, wrapped = excluded.wrapped,
         updated_at = excluded.updated_at`,
    )
    .bind(userId, kind, value.nonce, value.wrapped, now);
}

export function deviceWithUser(db: D1Database, deviceId: string) {
  return db
    .prepare(
      `SELECT d.*, u.status AS user_status FROM devices d JOIN users u ON u.id = d.user_id
       WHERE d.id = ?`,
    )
    .bind(deviceId)
    .first<DeviceWithUser>();
}

export function devicesOf(db: D1Database, userId: string) {
  return db
    .prepare(
      `SELECT id, user_id, label, platform, app_version, status, created_at, last_seen_at
       FROM devices WHERE user_id = ? ORDER BY created_at DESC LIMIT 50`,
    )
    .bind(userId)
    .all<Omit<DeviceRow, "secret_enc" | "secret_iv">>();
}

/** Statements that sign a device out: secret erased, refresh tokens gone. */
export function revokeDeviceStatements(db: D1Database, deviceId: string, now: number) {
  return [
    db
      .prepare(
        `UPDATE devices SET status = 'revoked', secret_enc = NULL, secret_iv = NULL, revoked_at = ?
         WHERE id = ? AND status = 'active'`,
      )
      .bind(now, deviceId),
    db.prepare("DELETE FROM refresh_tokens WHERE device_id = ?").bind(deviceId),
  ];
}

/** Every device of a user, optionally keeping one (the one changing the password). */
export function revokeAllDevicesStatements(
  db: D1Database,
  userId: string,
  now: number,
  keepDeviceId: string | null = null,
) {
  return [
    db
      .prepare(
        `UPDATE devices SET status = 'revoked', secret_enc = NULL, secret_iv = NULL, revoked_at = ?
         WHERE user_id = ? AND status = 'active' AND id IS NOT ?`,
      )
      .bind(now, userId, keepDeviceId),
    db
      .prepare(
        `DELETE FROM refresh_tokens WHERE device_id IN
           (SELECT id FROM devices WHERE user_id = ? AND id IS NOT ?)`,
      )
      .bind(userId, keepDeviceId),
  ];
}

/** Everything the server holds for a user (ADR-027 §1, account deletion). Children first. */
export function deleteUserStatements(db: D1Database, userId: string) {
  return [
    db
      .prepare(
        "DELETE FROM refresh_tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = ?)",
      )
      .bind(userId),
    db
      .prepare(
        "DELETE FROM request_nonces WHERE device_id IN (SELECT id FROM devices WHERE user_id = ?)",
      )
      .bind(userId),
    db.prepare("DELETE FROM devices WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM recovery_tickets WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM key_envelopes WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM recovery_credentials WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM password_credentials WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM identities WHERE user_id = ?").bind(userId),
    db.prepare("UPDATE abuse_events SET user_id = NULL WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM users WHERE id = ?").bind(userId),
  ];
}

export function audit(
  db: D1Database,
  actor: string,
  action: string,
  target: string | null,
  now: number,
) {
  return db
    .prepare("INSERT INTO admin_audit (actor, action, target, created_at) VALUES (?, ?, ?, ?)")
    .bind(actor, action, target, now);
}
