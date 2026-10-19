import type { DeviceRow } from "../db/devices";
import { parseOverrides } from "../db/devices";
import { log } from "../lib/log";

/** Per-device daily cost caps (ADR-004, ADR-015). */
export const CAP_TYPES = ["photo", "text", "recipe", "barcode", "correct"] as const;
export type CapType = (typeof CAP_TYPES)[number];
export type CapLimits = Record<CapType | "global", number>;

export const DEFAULT_CAPS: CapLimits = {
  photo: 10,
  recipe: 5,
  text: 5,
  barcode: 10,
  correct: 10,
  global: 40,
};

const DAY_MS = 24 * 60 * 60 * 1000;
const RESERVATION_TTL_MS = 5 * 60 * 1000;

export async function loadLimits(db: D1Database, device: DeviceRow): Promise<CapLimits> {
  const row = await db
    .prepare("SELECT value FROM config WHERE key = 'caps'")
    .first<{ value: string }>();
  const base = { ...DEFAULT_CAPS, ...(parseOverrides(row?.value ?? null) ?? {}) };
  return { ...base, ...(parseOverrides(device.cap_overrides) ?? {}) } as CapLimits;
}

export function isValidTimezone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** Local calendar date ("YYYY-MM-DD") in `tz` at `now`. */
export function dayKey(tz: string, now: number): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

/** UTC instant of the next local midnight in `tz` (ignores DST shifts within the day). */
export function nextMidnight(tz: string, now: number): number {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      hourCycle: "h23",
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
    })
      .formatToParts(now)
      .map((p) => [p.type, Number(p.value)]),
  ) as Record<string, number>;
  const localAsUtc = Date.UTC(
    parts.year ?? 1970,
    (parts.month ?? 1) - 1,
    parts.day ?? 1,
    parts.hour ?? 0,
    parts.minute ?? 0,
    parts.second ?? 0,
  );
  const offset = localAsUtc - Math.floor(now / 1000) * 1000;
  return Date.UTC(parts.year ?? 1970, (parts.month ?? 1) - 1, (parts.day ?? 1) + 1) - offset;
}

/**
 * The timezone used for this device's day boundary. A change is accepted at most once per
 * 24 h; otherwise the stored timezone wins (stops cap-reset abuse) and an abuse event is logged.
 */
export async function effectiveTimezone(
  db: D1Database,
  device: DeviceRow,
  requested: string | undefined,
  now: number,
): Promise<string> {
  const stored = device.tz;
  if (!requested || !isValidTimezone(requested) || requested === stored) return stored ?? "UTC";

  const canChange = !stored || !device.tz_changed_at || now - device.tz_changed_at >= DAY_MS;
  if (canChange) {
    await db
      .prepare("UPDATE devices SET tz = ?, tz_changed_at = ? WHERE token_id = ?")
      .bind(requested, stored ? now : null, device.token_id)
      .run();
    return requested;
  }
  await db
    .prepare("INSERT INTO abuse_events (device_id, kind, detail, created_at) VALUES (?, ?, ?, ?)")
    .bind(device.token_id, "tz_change_clamped", `${stored} -> ${requested}`, now)
    .run();
  log("warn", "tz_change_clamped", { device: device.token_id.slice(0, 4) });
  return stored;
}

export interface CapKey {
  deviceId: string;
  day: string;
  type: CapType;
  inputHash: string;
}

export type ReserveResult = "reserved" | "duplicate" | "in_flight" | "cap_reached" | "daily_cap";

/**
 * Atomically reserves one use. The same input on the same day never counts twice
 * ("duplicate" → serve the cached result). D1 serializes writes, so the conditional
 * INSERT cannot overshoot the limit under concurrency.
 */
export async function reserve(
  db: D1Database,
  key: CapKey,
  limits: CapLimits,
  now: number,
): Promise<ReserveResult> {
  const existing = await db
    .prepare(
      "SELECT status FROM cap_events WHERE device_id = ? AND day_key = ? AND cap_type = ? AND input_hash = ?",
    )
    .bind(key.deviceId, key.day, key.type, key.inputHash)
    .first<{ status: string }>();
  if (existing) return existing.status === "committed" ? "duplicate" : "in_flight";

  const result = await db
    .prepare(
      `INSERT INTO cap_events (device_id, day_key, cap_type, input_hash, status, created_at)
       SELECT ?1, ?2, ?3, ?4, 'reserved', ?5
       WHERE (SELECT COUNT(*) FROM cap_events WHERE device_id = ?1 AND day_key = ?2 AND cap_type = ?3) < ?6
         AND (SELECT COUNT(*) FROM cap_events WHERE device_id = ?1 AND day_key = ?2) < ?7
       ON CONFLICT DO NOTHING`,
    )
    .bind(key.deviceId, key.day, key.type, key.inputHash, now, limits[key.type], limits.global)
    .run();
  if (result.meta.changes === 1) return "reserved";

  const usage = await usageFor(db, key.deviceId, key.day);
  return usage[key.type] >= limits[key.type] ? "cap_reached" : "daily_cap";
}

export async function commit(db: D1Database, key: CapKey): Promise<void> {
  await db
    .prepare(
      "UPDATE cap_events SET status = 'committed' WHERE device_id = ? AND day_key = ? AND cap_type = ? AND input_hash = ?",
    )
    .bind(key.deviceId, key.day, key.type, key.inputHash)
    .run();
}

/** Failed requests don't count: drop the reservation. */
export async function release(db: D1Database, key: CapKey): Promise<void> {
  await db
    .prepare(
      "DELETE FROM cap_events WHERE device_id = ? AND day_key = ? AND cap_type = ? AND input_hash = ? AND status = 'reserved'",
    )
    .bind(key.deviceId, key.day, key.type, key.inputHash)
    .run();
}

export async function usageFor(
  db: D1Database,
  deviceId: string,
  day: string,
): Promise<Record<CapType, number>> {
  const { results } = await db
    .prepare(
      "SELECT cap_type, COUNT(*) AS used FROM cap_events WHERE device_id = ? AND day_key = ? GROUP BY cap_type",
    )
    .bind(deviceId, day)
    .all<{ cap_type: CapType; used: number }>();
  const usage = Object.fromEntries(CAP_TYPES.map((t) => [t, 0])) as Record<CapType, number>;
  for (const row of results) usage[row.cap_type] = row.used;
  return usage;
}

export async function capStatus(
  db: D1Database,
  device: DeviceRow,
  tz: string,
  now: number,
): Promise<{
  day: string;
  resetsAt: string;
  caps: Record<CapType, { used: number; limit: number }>;
  global: { used: number; limit: number };
}> {
  const day = dayKey(tz, now);
  const [limits, usage] = await Promise.all([
    loadLimits(db, device),
    usageFor(db, device.token_id, day),
  ]);
  const caps = Object.fromEntries(
    CAP_TYPES.map((t) => [t, { used: usage[t], limit: limits[t] }]),
  ) as Record<CapType, { used: number; limit: number }>;
  const used = CAP_TYPES.reduce((sum, t) => sum + usage[t], 0);
  return {
    day,
    resetsAt: new Date(nextMidnight(tz, now)).toISOString(),
    caps,
    global: { used, limit: limits.global },
  };
}

/** Cron: drop stale reservations left by crashed requests. */
export async function purgeStaleReservations(db: D1Database, now: number): Promise<void> {
  await db
    .prepare("DELETE FROM cap_events WHERE status = 'reserved' AND created_at < ?")
    .bind(now - RESERVATION_TTL_MS)
    .run();
}
