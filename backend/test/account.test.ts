import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { base64urlEncode, randomBytes } from "../src/lib/crypto";
import { errorCode, postJson, signUp, signed, signupMaterial } from "./helpers";

const TABLES_WITH_USER = [
  ["users", "id"],
  ["identities", "user_id"],
  ["password_credentials", "user_id"],
  ["recovery_credentials", "user_id"],
  ["key_envelopes", "user_id"],
  ["devices", "user_id"],
  ["recovery_tickets", "user_id"],
] as const;

async function rowsFor(userId: string): Promise<number> {
  let total = 0;
  for (const [table, column] of TABLES_WITH_USER) {
    const row = await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE ${column} = ?`)
      .bind(userId)
      .first<{ n: number }>();
    total += row?.n ?? 0;
  }
  return total;
}

describe("my account", () => {
  it("shows the account and its devices, and toggles product sharing", async () => {
    const account = await signUp();
    const data = (await (await signed(account.session, "/v1/account")).json()) as {
      user: { email: string; shareProducts: boolean };
      devices: { current: boolean; label: string }[];
    };
    expect(data.user).toMatchObject({ email: account.material.email, shareProducts: true });
    expect(data.devices).toEqual([
      expect.objectContaining({ current: true, label: "Test iPhone" }),
    ]);

    const off = await signed(account.session, "/v1/account", {
      method: "PATCH",
      body: { shareProducts: false },
    });
    expect(off.status).toBe(200);
    const after = (await (await signed(account.session, "/v1/account")).json()) as {
      user: { shareProducts: boolean };
    };
    expect(after.user.shareProducts).toBe(false);
  });

  it("replaces the recovery code with the password", async () => {
    const account = await signUp();
    const fresh = signupMaterial("unused");
    const body = {
      authKey: account.material.authKey,
      recovery: fresh.recovery,
      envelope: fresh.envelopes.recovery,
    };
    expect(
      await errorCode(
        await signed(account.session, "/v1/account/recovery", {
          method: "POST",
          body: { ...body, authKey: base64urlEncode(randomBytes(32)) },
        }),
      ),
    ).toBe("invalid_credentials");
    expect(
      (await signed(account.session, "/v1/account/recovery", { method: "POST", body })).status,
    ).toBe(200);

    const old = await postJson("/v1/auth/recovery/start", {
      email: account.material.email,
      recoveryAuth: account.material.recovery.authKey,
    });
    expect(await errorCode(old)).toBe("invalid_credentials");
    const start = await postJson("/v1/auth/recovery/start", {
      email: account.material.email,
      recoveryAuth: fresh.recovery.authKey,
    });
    expect(((await start.json()) as { envelope: unknown }).envelope).toEqual(
      fresh.envelopes.recovery,
    );
  });

  it("signs out one of my other devices, but not someone else's", async () => {
    const account = await signUp();
    const stranger = await signUp();
    const second = (await (
      await postJson("/v1/auth/login", {
        email: account.material.email,
        authKey: account.material.authKey,
        device: { label: "iPad", platform: "ios" },
      })
    ).json()) as { session: typeof account.session };
    const revoke = await signed(account.session, `/v1/account/devices/${second.session.deviceId}`, {
      method: "DELETE",
      body: {},
    });
    expect(revoke.status).toBe(200);
    expect(await errorCode(await signed(second.session, "/v1/account"))).toBe("device_revoked");
    const notMine = await signed(
      account.session,
      `/v1/account/devices/${stranger.session.deviceId}`,
      {
        method: "DELETE",
        body: {},
      },
    );
    expect(notMine.status).toBe(404);
  });
});

describe("account deletion (App Store 5.1.1(v))", () => {
  it("needs the password or recovery code, then removes everything about the user", async () => {
    const account = await signUp();
    expect(await rowsFor(account.userId)).toBeGreaterThan(5);

    const wrong = await signed(account.session, "/v1/account", {
      method: "DELETE",
      body: { authKey: base64urlEncode(randomBytes(32)) },
    });
    expect(await errorCode(wrong)).toBe("invalid_credentials");

    const res = await signed(account.session, "/v1/account", {
      method: "DELETE",
      body: { authKey: account.material.authKey },
    });
    expect(res.status).toBe(200);
    expect(await rowsFor(account.userId)).toBe(0);
    const tokens = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM refresh_tokens WHERE device_id = ?",
    )
      .bind(account.session.deviceId)
      .first<{ n: number }>();
    expect(tokens?.n).toBe(0);

    // The email is free again, and the old session is gone.
    expect(await errorCode(await signed(account.session, "/v1/account"))).toBe("unauthorized");
    const prelogin = (await (
      await postJson("/v1/auth/prelogin", { email: account.material.email })
    ).json()) as {
      salts: unknown;
    };
    expect(prelogin.salts).not.toEqual(account.material.salts);
  });

  it("works with the recovery code instead of the password", async () => {
    const account = await signUp();
    const res = await signed(account.session, "/v1/account", {
      method: "DELETE",
      body: { recoveryAuth: account.material.recovery.authKey },
    });
    expect(res.status).toBe(200);
    expect(await rowsFor(account.userId)).toBe(0);
  });
});
