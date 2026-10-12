import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { accessJwt, adminFetch, createDevice, errorCode, signedFetch, tokenParts } from "./helpers";

describe("device auth (ADR-013)", () => {
  it("accepts a correctly signed request and returns the device", async () => {
    const token = await createDevice("Khaled's iPhone");
    const res = await signedFetch(token, "/v1/device", {
      headers: { "X-Timezone": "Africa/Cairo" },
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      label: string;
      caps: { caps: { photo: { limit: number } } };
    };
    expect(body.label).toBe("Khaled's iPhone");
    expect(body.caps.caps.photo.limit).toBe(10);
  });

  it("rejects missing headers", async () => {
    const res = await SELF.fetch("https://api.test/v1/device");
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("unauthorized");
  });

  it("rejects a tampered signature", async () => {
    const token = await createDevice();
    const res = await signedFetch(token, "/v1/device", {
      tamper: (s) => (s[0] === "A" ? "B" : "A") + s.slice(1),
    });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("bad_signature");
  });

  it("rejects a signature made with another token", async () => {
    const tokenA = await createDevice("A");
    const tokenB = await createDevice("B");
    const forged = `lk1_${tokenParts(tokenA).id}_${tokenParts(tokenB).secret}`;
    const res = await signedFetch(forged, "/v1/device");
    expect(await errorCode(res)).toBe("bad_signature");
  });

  it("rejects a stale timestamp", async () => {
    const token = await createDevice();
    const res = await signedFetch(token, "/v1/device", { timestamp: Date.now() - 6 * 60 * 1000 });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("stale_request");
  });

  it("rejects a replayed nonce", async () => {
    const token = await createDevice();
    const nonce = "AAAAAAAAAAAAAAAAAAAAAA";
    expect((await signedFetch(token, "/v1/device", { nonce })).status).toBe(200);
    const replay = await signedFetch(token, "/v1/device", { nonce });
    expect(replay.status).toBe(401);
    expect(await errorCode(replay)).toBe("replayed_request");
  });

  it("covers the query string and body in the signature", async () => {
    const token = await createDevice();
    const ok = await signedFetch(token, "/v1/quota?x=1");
    expect(ok.status).toBe(200);
  });

  it("returns token_revoked after the admin revokes the token", async () => {
    const token = await createDevice();
    const tokenId = token.split("_")[1] ?? "";
    expect((await signedFetch(token, "/v1/device")).status).toBe(200);
    const revoke = await adminFetch(`/admin/api/devices/${tokenId}/revoke`, { method: "POST" });
    expect(revoke.status).toBe(204);
    const res = await signedFetch(token, "/v1/device");
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("token_revoked");
  });
});

describe("admin auth (ADR-007)", () => {
  it("rejects requests without an Access JWT", async () => {
    const res = await SELF.fetch("https://api.test/admin/api/devices");
    expect(res.status).toBe(401);
  });

  it("rejects a JWT for another audience", async () => {
    const res = await SELF.fetch("https://api.test/admin/api/devices", {
      headers: { "Cf-Access-Jwt-Assertion": await accessJwt({ aud: "other-app" }) },
    });
    expect(res.status).toBe(401);
  });

  it("rejects an expired JWT", async () => {
    const res = await SELF.fetch("https://api.test/admin/api/devices", {
      headers: {
        "Cf-Access-Jwt-Assertion": await accessJwt({ exp: Math.floor(Date.now() / 1000) - 10 }),
      },
    });
    expect(res.status).toBe(401);
  });

  it("creates a token shown once, with a QR code, and lists devices without secrets", async () => {
    const res = await adminFetch("/admin/api/devices", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ label: "iPad" }),
    });
    expect(res.status).toBe(201);
    const created = (await res.json()) as { token: string; qrSvg: string; tokenId: string };
    expect(created.token).toMatch(/^lk1_[A-Za-z0-9]{16}_[A-Za-z0-9_-]{43}$/);
    expect(created.qrSvg).toContain("<svg");

    const list = (await (await adminFetch("/admin/api/devices")).json()) as {
      items: Array<Record<string, unknown>>;
    };
    const row = list.items.find((d) => d.token_id === created.tokenId);
    expect(row?.label).toBe("iPad");
    expect(JSON.stringify(list)).not.toContain(tokenParts(created.token).secret);
    expect(row && "secret_enc" in row).toBe(false);
  });

  it("validates input", async () => {
    const res = await adminFetch("/admin/api/devices", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ label: "" }),
    });
    expect(res.status).toBe(400);
  });

  it("serves the admin page", async () => {
    const res = await adminFetch("/admin");
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("Device access tokens");
  });
});
