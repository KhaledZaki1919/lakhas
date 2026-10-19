import { Hono } from "hono";
import { deviceAuth, ipRateLimit } from "../auth/device";
import { ApiError } from "../lib/errors";
import { capStatus, effectiveTimezone } from "../services/caps";
import type { AppEnv } from "../types";

/** Versioned API: every route requires a valid HMAC-signed device token (ADR-013). */
export const v1 = new Hono<AppEnv>();

v1.use("*", ipRateLimit, deviceAuth);

v1.get("/device", async (c) => {
  const device = c.get("device");
  const now = Date.now();
  const tz = await effectiveTimezone(c.env.DB, device, c.req.header("X-Timezone"), now);
  return c.json({
    label: device.label,
    caps: await capStatus(c.env.DB, device, tz, now),
    serverTime: new Date(now).toISOString(),
  });
});

v1.get("/quota", async (c) => {
  const device = c.get("device");
  const now = Date.now();
  const tz = await effectiveTimezone(c.env.DB, device, c.req.header("X-Timezone"), now);
  return c.json(await capStatus(c.env.DB, device, tz, now));
});

// Implemented in later phases; until then they answer 501 with the standard envelope.
const planned: Array<[method: "get" | "post" | "delete", path: string]> = [
  ["delete", "/device"],
  ["post", "/analyze/photo"],
  ["post", "/analyze/text"],
  ["post", "/analyze/correct"],
  ["get", "/barcode/:code"],
  ["post", "/products/contribute"],
  ["post", "/recipes/import-link"],
  ["post", "/recipes/import-image"],
  ["get", "/foods/search"],
  ["get", "/explore"],
  ["post", "/explore/:id/vote"],
];

for (const [method, path] of planned) {
  v1[method](path, () => {
    throw new ApiError("not_implemented", 501);
  });
}
