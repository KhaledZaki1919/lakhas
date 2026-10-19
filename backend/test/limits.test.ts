import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { lockoutUntil } from "../src/auth/credentials";
import { LIMITS } from "../src/lib/limits";
import { reserve, usageToday } from "../src/services/quota";
import { apiFetch, errorCode, postJson } from "./helpers";

describe("free-tier guards (ADR-027 §11)", () => {
  it("rejects oversized bodies with 413 before reading them", async () => {
    const big = JSON.stringify({ email: "a@b.co", pad: "x".repeat(LIMITS.jsonBodyBytes) });
    const res = await postJson("/v1/auth/prelogin", JSON.parse(big));
    expect(res.status).toBe(413);
    expect(await errorCode(res)).toBe("payload_too_large");
  });

  it("rate-limits auth routes per IP", async () => {
    const ip = "203.0.113.7";
    const statuses: number[] = [];
    for (let i = 0; i < 12; i++) {
      statuses.push(
        (await postJson("/v1/auth/prelogin", { email: `x${i}@example.com` }, ip)).status,
      );
    }
    expect(statuses.slice(0, 10).every((s) => s === 200)).toBe(true);
    expect(statuses.at(-1)).toBe(429);
  });

  it("stops a daily quota at its limit and rolls back the refused unit", async () => {
    const now = Date.UTC(2026, 0, 1, 12);
    expect(await reserve(env.DB, "kv_writes", 3, 2, now)).toBe(2);
    expect(await reserve(env.DB, "kv_writes", 3, 1, now)).toBe(3);
    await expect(reserve(env.DB, "kv_writes", 3, 1, now)).rejects.toMatchObject({
      code: "quota_exceeded",
    });
    expect(await usageToday(env.DB, "kv_writes", now)).toBe(3);
    // A new day starts from zero.
    expect(await reserve(env.DB, "kv_writes", 3, 1, now + 24 * 60 * 60 * 1000)).toBe(1);
  });

  it("backs off failed sign-ins: free tries, then growing waits capped at an hour", () => {
    expect(lockoutUntil(4, 0)).toBeNull();
    expect(lockoutUntil(5, 0)).toBe(60_000);
    expect(lockoutUntil(7, 0)).toBe(4 * 60_000);
    expect(lockoutUntil(30, 0)).toBe(60 * 60_000);
  });
});

describe("public pages and errors", () => {
  it("serves the privacy policy and terms in Arabic by default and English on request", async () => {
    const ar = await apiFetch("/privacy");
    expect(ar.status).toBe(200);
    const arHtml = await ar.text();
    expect(arHtml).toContain('dir="rtl"');
    expect(arHtml).toContain("سياسة الخصوصية");
    const en = await (await apiFetch("/privacy?lang=en")).text();
    expect(en).toContain("Privacy policy");
    expect(en).toContain("never sent to our server");
    expect((await apiFetch("/terms?lang=en")).status).toBe(200);
    expect((await apiFetch("/privacy")).headers.get("Content-Security-Policy")).toContain(
      "default-src 'none'",
    );
  });

  it("answers unknown paths with a JSON not_found, in the app's language", async () => {
    const res = await apiFetch("/v1/nope", { headers: { "X-App-Lang": "en" } });
    expect(res.status).toBe(404);
    expect(await res.json()).toMatchObject({ error: { code: "not_found", message: "Not found." } });
  });

  it("has no admin routes on the API Worker", async () => {
    expect((await apiFetch("/admin")).status).toBe(404);
    expect((await apiFetch("/api/overview")).status).toBe(404);
  });

  it("reports health", async () => {
    expect(await (await apiFetch("/health")).json()).toMatchObject({ ok: true });
  });
});
