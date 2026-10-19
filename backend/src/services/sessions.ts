import {
  ACCESS_TTL_MS,
  REFRESH_TTL_MS,
  hashToken,
  mintAccessToken,
  newRefreshToken,
} from "../auth/tokens";
import { base64urlEncode, encryptSecret, randomBytes, randomId } from "../lib/crypto";

/** What the phone stores in the Keychain after sign up / sign in (ADR-027 §1). */
export interface SessionResponse {
  deviceId: string;
  /** 32 bytes, base64url. Sent once, here; the phone signs every request with it. */
  deviceSecret: string;
  accessToken: string;
  accessExpiresAt: number;
  refreshToken: string;
  refreshExpiresAt: number;
}

export interface DeviceInput {
  label: string;
  platform: string;
  appVersion?: string | undefined;
}

/** A new device with its first tokens. The statements are batched with the caller's own. */
export async function prepareSession(
  env: Env,
  userId: string,
  device: DeviceInput,
  now: number,
): Promise<{ statements: D1PreparedStatement[]; session: SessionResponse }> {
  const deviceId = randomId();
  const secret = randomBytes(32);
  const { ciphertext, iv } = await encryptSecret(env.DEVICE_ENC_KEY, secret);
  const tokens = await prepareTokens(env, userId, deviceId, now);
  return {
    statements: [
      env.DB.prepare(
        `INSERT INTO devices (id, user_id, label, platform, app_version, secret_enc, secret_iv,
                              status, created_at, last_seen_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, ?)`,
      ).bind(
        deviceId,
        userId,
        device.label,
        device.platform,
        device.appVersion ?? null,
        base64urlEncode(ciphertext),
        base64urlEncode(iv),
        now,
        now,
      ),
      ...tokens.statements,
    ],
    session: { deviceId, deviceSecret: base64urlEncode(secret), ...tokens.tokens },
  };
}

/** A fresh access token and a fresh single-use refresh token for an existing device. */
export async function prepareTokens(env: Env, userId: string, deviceId: string, now: number) {
  const refreshToken = newRefreshToken();
  const accessExpiresAt = now + ACCESS_TTL_MS;
  const refreshExpiresAt = now + REFRESH_TTL_MS;
  return {
    statements: [
      env.DB.prepare(
        "INSERT INTO refresh_tokens (token_hash, device_id, expires_at, created_at) VALUES (?, ?, ?, ?)",
      ).bind(await hashToken(refreshToken), deviceId, refreshExpiresAt, now),
    ],
    tokens: {
      accessToken: await mintAccessToken(env.ACCESS_TOKEN_KEY, {
        u: userId,
        d: deviceId,
        exp: accessExpiresAt,
      }),
      accessExpiresAt,
      refreshToken,
      refreshExpiresAt,
    },
  };
}
