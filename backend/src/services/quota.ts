import { ApiError } from "../lib/errors";

/** Daily counters for free-tier resources we must not exhaust (ADR-027 §11). */
export type QuotaResource = "kv_writes" | "kv_deletes";

export function dayKey(now: number): string {
  return new Date(now).toISOString().slice(0, 10);
}

/**
 * Reserves `amount` units of today's budget for `resource`. Throws `quota_exceeded` (503) once
 * the day's total would pass `dailyLimit`; the reservation is rolled back in that case.
 */
export async function reserve(
  db: D1Database,
  resource: QuotaResource,
  dailyLimit: number,
  amount = 1,
  now = Date.now(),
): Promise<number> {
  const day = dayKey(now);
  const row = await db
    .prepare(
      `INSERT INTO daily_usage (day, resource, count) VALUES (?, ?, ?)
       ON CONFLICT (day, resource) DO UPDATE SET count = count + excluded.count
       RETURNING count`,
    )
    .bind(day, resource, amount)
    .first<{ count: number }>();
  const count = row?.count ?? amount;
  if (count > dailyLimit) {
    await db
      .prepare("UPDATE daily_usage SET count = count - ? WHERE day = ? AND resource = ?")
      .bind(amount, day, resource)
      .run();
    throw new ApiError("quota_exceeded", 503, { resource });
  }
  return count;
}

export async function usageToday(
  db: D1Database,
  resource: QuotaResource,
  now = Date.now(),
): Promise<number> {
  const row = await db
    .prepare("SELECT count FROM daily_usage WHERE day = ? AND resource = ?")
    .bind(dayKey(now), resource)
    .first<{ count: number }>();
  return row?.count ?? 0;
}
