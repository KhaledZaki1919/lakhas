import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { getDevice } from "../src/db/devices";
import {
  type CapKey,
  type CapLimits,
  DEFAULT_CAPS,
  commit,
  dayKey,
  effectiveTimezone,
  nextMidnight,
  purgeStaleReservations,
  release,
  reserve,
  usageFor,
} from "../src/services/caps";
import { adminFetch, createDevice, signedFetch } from "./helpers";

const DAY = "2026-10-12";
const NOW = Date.UTC(2026, 9, 12, 10, 0, 0);
const key = (deviceId: string, inputHash: string, type: CapKey["type"] = "photo"): CapKey => ({
  deviceId,
  day: DAY,
  type,
  inputHash,
});

describe("day boundaries", () => {
  it("uses the local calendar date", () => {
    // 23:30 UTC on Oct 11 is already Oct 12 in Cairo (UTC+3 in October 2026)
    const t = Date.UTC(2026, 9, 11, 23, 30);
    expect(dayKey("UTC", t)).toBe("2026-10-11");
    expect(dayKey("Africa/Cairo", t)).toBe("2026-10-12");
  });

  it("computes the next local midnight", () => {
    const t = Date.UTC(2026, 9, 12, 10, 0);
    expect(new Date(nextMidnight("UTC", t)).toISOString()).toBe("2026-10-13T00:00:00.000Z");
    expect(new Date(nextMidnight("Asia/Riyadh", t)).toISOString()).toBe("2026-10-12T21:00:00.000Z");
  });
});

describe("reserve / commit / release (ADR-004)", () => {
  it("counts each new input once and dedupes same-day retries", async () => {
    const id = "dev-dedupe";
    expect(await reserve(env.DB, key(id, "a"), DEFAULT_CAPS, NOW)).toBe("reserved");
    expect(await reserve(env.DB, key(id, "a"), DEFAULT_CAPS, NOW)).toBe("in_flight");
    await commit(env.DB, key(id, "a"));
    expect(await reserve(env.DB, key(id, "a"), DEFAULT_CAPS, NOW)).toBe("duplicate");
    expect((await usageFor(env.DB, id, DAY)).photo).toBe(1);
  });

  it("doesn't count failed requests", async () => {
    const id = "dev-release";
    expect(await reserve(env.DB, key(id, "x"), DEFAULT_CAPS, NOW)).toBe("reserved");
    await release(env.DB, key(id, "x"));
    expect((await usageFor(env.DB, id, DAY)).photo).toBe(0);
  });

  it("enforces the per-type cap", async () => {
    const id = "dev-cap";
    const limits: CapLimits = { ...DEFAULT_CAPS, text: 2 };
    for (const h of ["1", "2"]) {
      expect(await reserve(env.DB, key(id, h, "text"), limits, NOW)).toBe("reserved");
      await commit(env.DB, key(id, h, "text"));
    }
    expect(await reserve(env.DB, key(id, "3", "text"), limits, NOW)).toBe("cap_reached");
    expect(await reserve(env.DB, key(id, "4", "photo"), limits, NOW)).toBe("reserved");
  });

  it("enforces the global cap across types", async () => {
    const id = "dev-global";
    const limits: CapLimits = { ...DEFAULT_CAPS, global: 2 };
    expect(await reserve(env.DB, key(id, "p", "photo"), limits, NOW)).toBe("reserved");
    expect(await reserve(env.DB, key(id, "t", "text"), limits, NOW)).toBe("reserved");
    expect(await reserve(env.DB, key(id, "b", "barcode"), limits, NOW)).toBe("daily_cap");
  });

  it("doesn't overshoot under concurrent reservations", async () => {
    const id = "dev-race";
    const limits: CapLimits = { ...DEFAULT_CAPS, photo: 3 };
    const results = await Promise.all(
      Array.from({ length: 8 }, (_, i) => reserve(env.DB, key(id, `r${i}`), limits, NOW)),
    );
    expect(results.filter((r) => r === "reserved")).toHaveLength(3);
    expect((await usageFor(env.DB, id, DAY)).photo).toBe(3);
  });

  it("purges stale reservations", async () => {
    const id = "dev-stale";
    await reserve(env.DB, key(id, "s"), DEFAULT_CAPS, NOW);
    await purgeStaleReservations(env.DB, NOW + 6 * 60 * 1000);
    expect((await usageFor(env.DB, id, DAY)).photo).toBe(0);
  });
});

describe("timezone clamping", () => {
  it("accepts the first timezone, then at most one change per 24 h", async () => {
    const token = await createDevice("tz");
    const tokenId = token.split("_")[1] ?? "";
    const load = async () => {
      const d = await getDevice(env.DB, tokenId);
      if (!d) throw new Error("missing device");
      return d;
    };

    expect(await effectiveTimezone(env.DB, await load(), "Africa/Cairo", NOW)).toBe("Africa/Cairo");
    expect(await effectiveTimezone(env.DB, await load(), "Asia/Dubai", NOW + 1000)).toBe(
      "Asia/Dubai",
    );
    // a second change within 24 h is clamped to the stored zone
    expect(await effectiveTimezone(env.DB, await load(), "Pacific/Kiritimati", NOW + 2000)).toBe(
      "Asia/Dubai",
    );
    // after 24 h the change is accepted
    expect(
      await effectiveTimezone(env.DB, await load(), "Pacific/Kiritimati", NOW + 1000 + 86_400_000),
    ).toBe("Pacific/Kiritimati");
    // invalid zones are ignored
    expect(await effectiveTimezone(env.DB, await load(), "Not/AZone", NOW + 90_000_000)).toBe(
      "Pacific/Kiritimati",
    );
  });
});

describe("caps via the API", () => {
  it("reports usage and per-device overrides from the admin panel", async () => {
    const token = await createDevice("caps");
    const tokenId = token.split("_")[1] ?? "";
    const patch = await adminFetch(`/admin/api/devices/${tokenId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ capOverrides: { photo: 25 } }),
    });
    expect(patch.status).toBe(204);

    const res = await signedFetch(token, "/v1/quota", {
      headers: { "X-Timezone": "Africa/Cairo" },
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      caps: Record<string, { used: number; limit: number }>;
      global: { used: number; limit: number };
    };
    expect(body.caps.photo).toEqual({ used: 0, limit: 25 });
    expect(body.caps.text).toEqual({ used: 0, limit: 5 });
    expect(body.global.limit).toBe(40);
  });
});
