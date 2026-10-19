/** Data access for the `devices` table (ADR-013). Timestamps are Unix ms. */

export type DeviceStatus = "active" | "revoked";

export interface DeviceRow {
  token_id: string;
  label: string;
  secret_enc: string | null;
  secret_iv: string | null;
  status: DeviceStatus;
  created_at: number;
  activated_at: number | null;
  last_seen_at: number | null;
  revoked_at: number | null;
  tz: string | null;
  tz_changed_at: number | null;
  lang: "ar" | "en" | null;
  improve_opt_in: number;
  cap_overrides: string | null;
}

/** Fields safe to show in the admin panel (never the secret). */
export type DeviceSummary = Pick<
  DeviceRow,
  "token_id" | "label" | "status" | "created_at" | "activated_at" | "last_seen_at" | "revoked_at"
> & { cap_overrides: Record<string, number> | null };

export function getDevice(db: D1Database, tokenId: string): Promise<DeviceRow | null> {
  return db.prepare("SELECT * FROM devices WHERE token_id = ?").bind(tokenId).first<DeviceRow>();
}

export async function insertDevice(
  db: D1Database,
  device: { tokenId: string; label: string; secretEnc: string; secretIv: string; now: number },
): Promise<void> {
  await db
    .prepare(
      "INSERT INTO devices (token_id, label, secret_enc, secret_iv, status, created_at) VALUES (?, ?, ?, ?, 'active', ?)",
    )
    .bind(device.tokenId, device.label, device.secretEnc, device.secretIv, device.now)
    .run();
}

export async function listDevices(db: D1Database): Promise<DeviceSummary[]> {
  const { results } = await db
    .prepare(
      "SELECT token_id, label, status, created_at, activated_at, last_seen_at, revoked_at, cap_overrides FROM devices ORDER BY created_at DESC",
    )
    .all<Omit<DeviceSummary, "cap_overrides"> & { cap_overrides: string | null }>();
  return results.map((row) => ({ ...row, cap_overrides: parseOverrides(row.cap_overrides) }));
}

export async function updateDevice(
  db: D1Database,
  tokenId: string,
  changes: { label?: string; capOverrides?: Record<string, number> | null },
): Promise<boolean> {
  const sets: string[] = [];
  const values: (string | null)[] = [];
  if (changes.label !== undefined) {
    sets.push("label = ?");
    values.push(changes.label);
  }
  if (changes.capOverrides !== undefined) {
    sets.push("cap_overrides = ?");
    values.push(changes.capOverrides ? JSON.stringify(changes.capOverrides) : null);
  }
  if (sets.length === 0) return true;
  const result = await db
    .prepare(`UPDATE devices SET ${sets.join(", ")} WHERE token_id = ?`)
    .bind(...values, tokenId)
    .run();
  return result.meta.changes > 0;
}

/** Revokes the token and wipes its secret so it can never verify again. */
export async function revokeDevice(db: D1Database, tokenId: string, now: number): Promise<boolean> {
  const result = await db
    .prepare(
      "UPDATE devices SET status = 'revoked', revoked_at = ?, secret_enc = NULL, secret_iv = NULL WHERE token_id = ? AND status = 'active'",
    )
    .bind(now, tokenId)
    .run();
  return result.meta.changes > 0;
}

export async function markSeen(
  db: D1Database,
  tokenId: string,
  now: number,
  lang: "ar" | "en",
): Promise<void> {
  await db
    .prepare(
      "UPDATE devices SET last_seen_at = ?, activated_at = COALESCE(activated_at, ?), lang = ? WHERE token_id = ?",
    )
    .bind(now, now, lang, tokenId)
    .run();
}

export function parseOverrides(json: string | null): Record<string, number> | null {
  if (!json) return null;
  try {
    const value: unknown = JSON.parse(json);
    if (value && typeof value === "object") {
      return Object.fromEntries(
        Object.entries(value).filter(
          (entry): entry is [string, number] => typeof entry[1] === "number",
        ),
      );
    }
  } catch {
    // fall through
  }
  return null;
}
