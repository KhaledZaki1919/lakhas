import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { mintAccessToken } from "../src/auth/tokens";
import { base64urlEncode, randomBytes } from "../src/lib/crypto";
import {
  adminFetch,
  createInvite,
  errorCode,
  postJson,
  signUp,
  signed,
  signupMaterial,
} from "./helpers";

const newKey = () => base64urlEncode(randomBytes(32));

describe("sign up", () => {
  it("needs a valid invite and creates a user, a device and a session", async () => {
    const code = await createInvite();
    const material = signupMaterial(code);
    const res = await postJson("/v1/auth/signup", material);
    expect(res.status).toBe(201);
    const data = (await res.json()) as {
      user: { email: string };
      session: Record<string, unknown>;
    };
    expect(data.user.email).toBe(material.email);
    expect(data.session).toMatchObject({
      deviceId: expect.stringMatching(/^[A-Za-z0-9_-]{22}$/),
      deviceSecret: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/),
      accessToken: expect.stringMatching(/^v1\./),
      refreshToken: expect.stringMatching(/^rt_/),
    });

    // Nothing secret is stored in clear: no authKey, no recovery key, no device secret.
    const dump = JSON.stringify(
      await env.DB.batch([
        env.DB.prepare("SELECT * FROM password_credentials"),
        env.DB.prepare("SELECT * FROM recovery_credentials"),
        env.DB.prepare("SELECT * FROM devices"),
      ]),
    );
    expect(dump).not.toContain(material.authKey);
    expect(dump).not.toContain(material.recovery.authKey);
    expect(dump).not.toContain(data.session.deviceSecret as string);
  });

  it("rejects an unknown, stopped, expired or used-up invite", async () => {
    expect(
      await errorCode(await postJson("/v1/auth/signup", signupMaterial("NOPE-NOPE-NOPE"))),
    ).toBe("invalid_invite");

    const once = await createInvite(undefined, { maxUses: 1 });
    expect((await postJson("/v1/auth/signup", signupMaterial(once))).status).toBe(201);
    expect(await errorCode(await postJson("/v1/auth/signup", signupMaterial(once)))).toBe(
      "invalid_invite",
    );

    const old = await createInvite();
    await createInvite(); // a new code stops the old one
    expect(await errorCode(await postJson("/v1/auth/signup", signupMaterial(old)))).toBe(
      "invalid_invite",
    );

    const expired = await createInvite(undefined, { expiresInDays: 1 });
    await env.DB.prepare("UPDATE invites SET expires_at = 1 WHERE code = ?").bind(expired).run();
    expect(await errorCode(await postJson("/v1/auth/signup", signupMaterial(expired)))).toBe(
      "invalid_invite",
    );

    const events = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM abuse_events WHERE kind = 'invalid_invite'",
    ).first<{ n: number }>();
    expect(events?.n).toBeGreaterThanOrEqual(4);
  });

  it("accepts the invite code in any case and with spaces", async () => {
    const code = await createInvite("Friends-2026");
    const res = await postJson("/v1/auth/signup", signupMaterial(`  ${code.toLowerCase()} `));
    expect(res.status).toBe(201);
  });

  it("refuses a second account for the same email (case-insensitive) without using the invite", async () => {
    const code = await createInvite(undefined, { maxUses: 5 });
    const first = signupMaterial(code, "Same@Example.com");
    expect((await postJson("/v1/auth/signup", first)).status).toBe(201);
    const again = signupMaterial(code, "same@example.com");
    expect(await errorCode(await postJson("/v1/auth/signup", again))).toBe("email_taken");
    const invite = await env.DB.prepare("SELECT uses FROM invites WHERE code = ?")
      .bind(code)
      .first<{ uses: number }>();
    expect(invite?.uses).toBe(1);
  });

  it("validates key material sizes and the KDF", async () => {
    const code = await createInvite();
    const weak = { ...signupMaterial(code), kdf: { name: "pbkdf2-sha256", iterations: 100_000 } };
    expect(await errorCode(await postJson("/v1/auth/signup", weak))).toBe("invalid_request");
    const shortKey = { ...signupMaterial(code), authKey: base64urlEncode(randomBytes(16)) };
    expect(await errorCode(await postJson("/v1/auth/signup", shortKey))).toBe("invalid_request");
  });
});

describe("prelogin", () => {
  it("returns the account's salts, and stable decoys for unknown emails", async () => {
    const account = await signUp();
    const known = (await (
      await postJson("/v1/auth/prelogin", { email: account.material.email })
    ).json()) as {
      kdf: { iterations: number };
      salts: Record<string, string>;
      recoverySalt: string;
    };
    expect(known.salts).toEqual(account.material.salts);
    expect(known.recoverySalt).toBe(account.material.recovery.salt);
    expect(known.kdf.iterations).toBe(600_000);

    const a = await (await postJson("/v1/auth/prelogin", { email: "nobody@example.com" })).json();
    const b = await (await postJson("/v1/auth/prelogin", { email: "NOBODY@example.com" })).json();
    expect(a).toEqual(b);
    expect((a as { salts: { kdf: string } }).salts.kdf).toMatch(/^[A-Za-z0-9_-]{22}$/);
  });
});

describe("sign in", () => {
  it("returns a new device session and the password envelope", async () => {
    const account = await signUp();
    const res = await postJson("/v1/auth/login", {
      email: account.material.email,
      authKey: account.material.authKey,
      device: { label: "Second iPhone", platform: "ios" },
    });
    expect(res.status).toBe(200);
    const data = (await res.json()) as {
      session: { deviceId: string };
      keys: { envelope: unknown };
    };
    expect(data.session.deviceId).not.toBe(account.session.deviceId);
    expect(data.keys.envelope).toEqual(account.material.envelopes.password);
  });

  it("rejects a wrong key or unknown email the same way, and locks after 5 failures", async () => {
    const account = await signUp();
    const attempt = (authKey: string) =>
      postJson("/v1/auth/login", {
        email: account.material.email,
        authKey,
        device: { label: "x", platform: "ios" },
      });
    expect(
      await errorCode(
        await postJson("/v1/auth/login", {
          email: "ghost@example.com",
          authKey: newKey(),
          device: { label: "x", platform: "ios" },
        }),
      ),
    ).toBe("invalid_credentials");
    for (let i = 0; i < 5; i++)
      expect(await errorCode(await attempt(newKey()))).toBe("invalid_credentials");
    // Locked now, even with the right key.
    const locked = await attempt(account.material.authKey);
    expect(locked.status).toBe(429);
    expect(await errorCode(locked)).toBe("too_many_attempts");
  });

  it("refuses a disabled account", async () => {
    const account = await signUp();
    await adminFetch(`/api/users/${account.userId}/status`, {
      method: "POST",
      body: JSON.stringify({ status: "disabled" }),
    });
    const res = await postJson("/v1/auth/login", {
      email: account.material.email,
      authKey: account.material.authKey,
      device: { label: "x", platform: "ios" },
    });
    expect(await errorCode(res)).toBe("account_disabled");
  });
});

describe("signed requests (LK2)", () => {
  it("accepts a correctly signed request", async () => {
    const { session } = await signUp();
    expect((await signed(session, "/v1/account")).status).toBe(200);
  });

  it("rejects a tampered body, a wrong signature, a replay and a stale timestamp", async () => {
    const { session } = await signUp();
    const tampered = await signed(session, "/v1/account", {
      method: "PATCH",
      body: { shareProducts: false },
      tamper: true,
    });
    expect(await errorCode(tampered)).toBe("bad_signature");

    const other = await signUp();
    const wrongSecret = await signed(
      { ...session, deviceSecret: other.session.deviceSecret },
      "/v1/account",
    );
    expect(await errorCode(wrongSecret)).toBe("bad_signature");

    const nonce = base64urlEncode(randomBytes(16));
    expect((await signed(session, "/v1/account", { nonce })).status).toBe(200);
    expect(await errorCode(await signed(session, "/v1/account", { nonce }))).toBe(
      "replayed_request",
    );

    const stale = await signed(session, "/v1/account", { timestamp: Date.now() - 6 * 60 * 1000 });
    expect(await errorCode(stale)).toBe("stale_request");
  });

  it("needs an access token for this device, and says when it expired", async () => {
    const a = await signUp();
    const b = await signUp();
    expect(await errorCode(await signed(a.session, "/v1/account", { accessToken: null }))).toBe(
      "unauthorized",
    );
    expect(
      await errorCode(
        await signed(a.session, "/v1/account", { accessToken: b.session.accessToken }),
      ),
    ).toBe("unauthorized");
    const expired = await mintAccessToken(env.ACCESS_TOKEN_KEY, {
      u: a.userId,
      d: a.session.deviceId,
      exp: Date.now() - 1,
    });
    const res = await signed(a.session, "/v1/account", { accessToken: expired });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("session_expired");
  });
});

describe("refresh", () => {
  it("rotates the refresh token, and a reused one signs the device out", async () => {
    const { session } = await signUp();
    const first = await signed(session, "/v1/auth/refresh", {
      method: "POST",
      body: { refreshToken: session.refreshToken },
      accessToken: null,
    });
    expect(first.status).toBe(200);
    const tokens = (await first.json()) as { accessToken: string; refreshToken: string };
    expect(tokens.refreshToken).not.toBe(session.refreshToken);
    expect((await signed({ ...session, ...tokens }, "/v1/account")).status).toBe(200);

    const reuse = await signed(session, "/v1/auth/refresh", {
      method: "POST",
      body: { refreshToken: session.refreshToken },
      accessToken: null,
    });
    expect(await errorCode(reuse)).toBe("device_revoked");
    expect(await errorCode(await signed({ ...session, ...tokens }, "/v1/account"))).toBe(
      "device_revoked",
    );
  });

  it("won't refresh another device's token", async () => {
    const a = await signUp();
    const b = await signUp();
    const res = await signed(a.session, "/v1/auth/refresh", {
      method: "POST",
      body: { refreshToken: b.session.refreshToken },
      accessToken: null,
    });
    expect(await errorCode(res)).toBe("unauthorized");
  });
});

describe("sign out and passwords", () => {
  it("sign out revokes only this device", async () => {
    const account = await signUp();
    const second = (await (
      await postJson("/v1/auth/login", {
        email: account.material.email,
        authKey: account.material.authKey,
        device: { label: "iPad", platform: "ios" },
      })
    ).json()) as { session: typeof account.session };
    expect(
      (await signed(account.session, "/v1/auth/logout", { method: "POST", body: {} })).status,
    ).toBe(200);
    expect(await errorCode(await signed(account.session, "/v1/account"))).toBe("device_revoked");
    expect((await signed(second.session, "/v1/account")).status).toBe(200);
  });

  it("changing the password keeps this device, signs out the others, and replaces the envelope", async () => {
    const account = await signUp();
    const other = (await (
      await postJson("/v1/auth/login", {
        email: account.material.email,
        authKey: account.material.authKey,
        device: { label: "Old phone", platform: "ios" },
      })
    ).json()) as { session: typeof account.session };
    const fresh = signupMaterial("unused");
    const change = {
      currentAuthKey: account.material.authKey,
      authKey: fresh.authKey,
      kdf: fresh.kdf,
      salts: fresh.salts,
      envelope: fresh.envelopes.password,
    };
    expect(
      await errorCode(
        await signed(account.session, "/v1/auth/password", {
          method: "POST",
          body: { ...change, currentAuthKey: newKey() },
        }),
      ),
    ).toBe("invalid_credentials");
    expect(
      (await signed(account.session, "/v1/auth/password", { method: "POST", body: change })).status,
    ).toBe(200);
    expect((await signed(account.session, "/v1/account")).status).toBe(200);
    expect(await errorCode(await signed(other.session, "/v1/account"))).toBe("device_revoked");

    const login = await postJson("/v1/auth/login", {
      email: account.material.email,
      authKey: fresh.authKey,
      device: { label: "x", platform: "ios" },
    });
    expect(((await login.json()) as { keys: { envelope: unknown } }).keys.envelope).toEqual(
      fresh.envelopes.password,
    );
    const prelogin = (await (
      await postJson("/v1/auth/prelogin", { email: account.material.email })
    ).json()) as {
      salts: unknown;
    };
    expect(prelogin.salts).toEqual(fresh.salts);
  });
});

describe("recovery code reset", () => {
  it("proves the code, returns the recovery envelope, then sets a new password and signs out everyone", async () => {
    const account = await signUp();
    const start = await postJson("/v1/auth/recovery/start", {
      email: account.material.email,
      recoveryAuth: account.material.recovery.authKey,
    });
    expect(start.status).toBe(200);
    const { ticket, envelope } = (await start.json()) as { ticket: string; envelope: unknown };
    expect(envelope).toEqual(account.material.envelopes.recovery);

    const fresh = signupMaterial("unused");
    const reset = await postJson("/v1/auth/recovery/reset", {
      ticket,
      authKey: fresh.authKey,
      kdf: fresh.kdf,
      salts: fresh.salts,
      envelope: fresh.envelopes.password,
      device: { label: "New phone", platform: "ios" },
    });
    expect(reset.status).toBe(200);
    const { session } = (await reset.json()) as { session: typeof account.session };
    expect((await signed(session, "/v1/account")).status).toBe(200);
    expect(await errorCode(await signed(account.session, "/v1/account"))).toBe("device_revoked");

    // The ticket works once.
    const again = await postJson("/v1/auth/recovery/reset", {
      ticket,
      authKey: fresh.authKey,
      kdf: fresh.kdf,
      salts: fresh.salts,
      envelope: fresh.envelopes.password,
      device: { label: "x", platform: "ios" },
    });
    expect(await errorCode(again)).toBe("unauthorized");
  });

  it("rejects a wrong code and locks after 5 tries", async () => {
    const account = await signUp();
    for (let i = 0; i < 5; i++) {
      const res = await postJson("/v1/auth/recovery/start", {
        email: account.material.email,
        recoveryAuth: newKey(),
      });
      expect(await errorCode(res)).toBe("invalid_credentials");
    }
    const locked = await postJson("/v1/auth/recovery/start", {
      email: account.material.email,
      recoveryAuth: account.material.recovery.authKey,
    });
    expect(await errorCode(locked)).toBe("too_many_attempts");
  });
});
