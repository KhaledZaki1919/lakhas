import { SELF } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

type ErrorEnvelope = { error: { code: string; message: string; retryable: boolean } };

describe("health", () => {
  it("returns ok and the version without auth", async () => {
    const res = await SELF.fetch("https://api.test/health");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, version: "0.1.0" });
  });
});

describe("error envelope", () => {
  it("answers unknown routes with a localized not_found (Arabic by default)", async () => {
    const res = await SELF.fetch("https://api.test/nope");
    expect(res.status).toBe(404);
    const body = (await res.json()) as ErrorEnvelope;
    expect(body.error).toEqual({ code: "not_found", retryable: false, message: "غير موجود." });
  });

  it("uses English when X-App-Lang is en", async () => {
    const res = await SELF.fetch("https://api.test/nope", { headers: { "X-App-Lang": "en" } });
    const body = (await res.json()) as ErrorEnvelope;
    expect(body.error.message).toBe("Not found.");
  });

  it("marks planned v1 routes as not implemented yet", async () => {
    const res = await SELF.fetch("https://api.test/v1/quota");
    expect(res.status).toBe(501);
    const body = (await res.json()) as ErrorEnvelope;
    expect(body.error.code).toBe("not_implemented");
  });
});

describe("bindings", () => {
  it("applies migrations and seeds the default caps", async () => {
    const row = await env.DB.prepare("SELECT value FROM config WHERE key = 'caps'").first<{
      value: string;
    }>();
    expect(JSON.parse(row?.value ?? "{}")).toEqual({
      photo: 10,
      recipe: 5,
      text: 5,
      barcode: 10,
      correct: 10,
      global: 40,
    });
  });

  it("exposes KV and R2", async () => {
    await env.CACHE.put("k", "v");
    expect(await env.CACHE.get("k")).toBe("v");
    await env.MEDIA.put("probe.txt", "hello");
    expect(await (await env.MEDIA.get("probe.txt"))?.text()).toBe("hello");
  });
});
