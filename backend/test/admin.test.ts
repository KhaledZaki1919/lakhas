import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { randomInviteCode } from "../src/admin/api";
import { accessJwt, adminFetch, errorCode, signUp, signed } from "./helpers";

describe("admin Worker access (Cloudflare Access JWT)", () => {
  it("refuses requests without a valid Access token", async () => {
    expect((await adminFetch("/", {}, null)).status).toBe(401);
    expect(
      (await adminFetch("/api/overview", {}, await accessJwt({ aud: "other-app" }))).status,
    ).toBe(401);
    expect(
      (
        await adminFetch(
          "/api/overview",
          {},
          await accessJwt({ exp: Math.floor(Date.now() / 1000) - 10 }),
        )
      ).status,
    ).toBe(401);
    expect(
      (
        await adminFetch(
          "/api/overview",
          {},
          await accessJwt({ iss: "https://evil.cloudflareaccess.com" }),
        )
      ).status,
    ).toBe(401);
    const forged = (await accessJwt()).replace(/\.[^.]+$/, ".AAAA");
    expect((await adminFetch("/api/overview", {}, forged)).status).toBe(401);
  });

  it("serves the panel with a strict CSP and the admin's email", async () => {
    const page = await adminFetch("/");
    expect(page.status).toBe(200);
    expect(page.headers.get("Content-Security-Policy")).toContain("script-src 'self'");
    expect(page.headers.get("X-Frame-Options")).toBe("DENY");
    expect(await page.text()).toContain("Lakhas admin");
    expect((await adminFetch("/app.js")).headers.get("Content-Type")).toContain("javascript");
    expect(await (await adminFetch("/api/me")).json()).toEqual({ email: "admin@example.com" });
  });

  it("needs the CSRF header and a same-origin Origin for changes", async () => {
    const noHeader = await adminFetch("/api/invites", {
      method: "POST",
      body: "{}",
      headers: { "X-Lakhas-Admin": "0" },
    });
    expect(noHeader.status).toBe(403);
    const crossSite = await adminFetch("/api/invites", {
      method: "POST",
      body: "{}",
      headers: { Origin: "https://evil.example" },
    });
    expect(crossSite.status).toBe(403);
  });
});

describe("admin API", () => {
  it("creates invite codes, stops older ones, and shows the current one", async () => {
    const made = await adminFetch("/api/invites", {
      method: "POST",
      body: JSON.stringify({ maxUses: 3 }),
    });
    expect(made.status).toBe(201);
    const { code } = (await made.json()) as { code: string };
    expect(code).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    const overview = (await (await adminFetch("/api/overview")).json()) as {
      invite: { code: string };
    };
    expect(overview.invite.code).toBe(code);

    const custom = await adminFetch("/api/invites", {
      method: "POST",
      body: JSON.stringify({ code: "family-2026" }),
    });
    expect(((await custom.json()) as { code: string }).code).toBe("FAMILY-2026");
    const reused = await adminFetch("/api/invites", {
      method: "POST",
      body: JSON.stringify({ code: "FAMILY-2026" }),
    });
    expect(reused.status).toBe(400);

    const { invites } = (await (await adminFetch("/api/invites")).json()) as {
      invites: { code: string; active: number }[];
    };
    expect(invites.filter((i) => i.active === 1).map((i) => i.code)).toEqual(["FAMILY-2026"]);

    await adminFetch("/api/invites/deactivate", { method: "POST", body: "{}" });
    const after = (await (await adminFetch("/api/overview")).json()) as { invite: unknown };
    expect(after.invite).toBeNull();
  });

  it("lists and searches users, and disabling one signs out all their devices at once", async () => {
    const account = await signUp();
    const { users } = (await (
      await adminFetch(`/api/users?q=${encodeURIComponent(account.material.email.slice(0, 12))}`)
    ).json()) as { users: { id: string; email: string; devices: number }[] };
    expect(users.find((u) => u.id === account.userId)).toMatchObject({
      email: account.material.email,
      devices: 1,
    });

    const disable = await adminFetch(`/api/users/${account.userId}/status`, {
      method: "POST",
      body: JSON.stringify({ status: "disabled" }),
    });
    expect(disable.status).toBe(200);
    const res = await signed(account.session, "/v1/account");
    expect(["device_revoked", "account_disabled"]).toContain(await errorCode(res));

    const detail = (await (await adminFetch(`/api/users/${account.userId}`)).json()) as {
      user: { status: string };
      devices: { status: string }[];
    };
    expect(detail.user.status).toBe("disabled");
    expect(detail.devices.every((d) => d.status === "revoked")).toBe(true);
    expect(
      (
        await adminFetch("/api/users/nope/status", {
          method: "POST",
          body: JSON.stringify({ status: "active" }),
        })
      ).status,
    ).toBe(404);
  });

  it("signs out a single device", async () => {
    const account = await signUp();
    const res = await adminFetch(`/api/devices/${account.session.deviceId}/revoke`, {
      method: "POST",
      body: "{}",
    });
    expect(res.status).toBe(200);
    expect(await errorCode(await signed(account.session, "/v1/account"))).toBe("device_revoked");
  });

  it("audits admin actions with the admin's email", async () => {
    await adminFetch("/api/invites", { method: "POST", body: "{}" });
    const { entries } = (await (await adminFetch("/api/audit")).json()) as {
      entries: { actor: string; action: string }[];
    };
    expect(entries[0]).toMatchObject({ actor: "admin@example.com", action: "invite_created" });
  });

  it("makes unambiguous random invite codes", () => {
    const codes = new Set(Array.from({ length: 200 }, randomInviteCode));
    expect(codes.size).toBe(200);
    for (const code of codes) expect(code).not.toMatch(/[01OIL]/);
  });

  it("reports storage and the KV write guard", async () => {
    const overview = (await (await adminFetch("/api/overview")).json()) as {
      today: { kvWrites: number; kvWritesLimit: number };
    };
    expect(overview.today.kvWritesLimit).toBe(500);
    expect(typeof overview.today.kvWrites).toBe("number");
    expect(env.DB).toBeDefined();
  });
});
