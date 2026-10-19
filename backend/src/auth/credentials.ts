import { z } from "zod";
import { base64urlDecode, base64urlEncode, hmacWithSecret, timingSafeEqual } from "../lib/crypto";

/**
 * Account key material (ADR-027 §1–2). The phone stretches the password (PBKDF2-SHA256) and
 * derives two independent keys with HKDF; only `authKey` is ever sent. The server stores a
 * peppered HMAC of it and never sees the password or the backup key.
 */
export const KDF_NAME = "pbkdf2-sha256";
export const KDF_MIN_ITERATIONS = 600_000;
export const KDF_MAX_ITERATIONS = 10_000_000;

const b64url = (bytes: number) =>
  z
    .string()
    .regex(/^[A-Za-z0-9_-]+$/)
    .refine((text) => base64urlDecode(text)?.length === bytes, `must be ${bytes} bytes`);

export const salt = b64url(16);
export const key32 = b64url(32);

export const email = z
  .string()
  .trim()
  .toLowerCase()
  .max(254)
  .regex(/^[^\s@]+@[^\s@]+\.[^\s@]+$/);

export const kdfParams = z.object({
  name: z.literal(KDF_NAME),
  iterations: z.number().int().min(KDF_MIN_ITERATIONS).max(KDF_MAX_ITERATIONS),
});

export const salts = z.object({ kdf: salt, auth: salt, enc: salt });

/** The 32-byte data key wrapped with AES-GCM on the phone: 12-byte nonce, 48-byte box. */
export const envelope = z.object({ nonce: b64url(12), wrapped: b64url(48) });

export const deviceInfo = z.object({
  label: z.string().trim().min(1).max(60),
  platform: z.enum(["ios"]),
  appVersion: z.string().trim().max(20).optional(),
});

export const recoveryMaterial = z.object({ salt, authKey: key32 });

export async function verifierFor(pepper: string, kind: "auth" | "recovery", key: string) {
  return base64urlEncode(await hmacWithSecret(pepper, `lakhas/verifier/${kind}/v1:${key}`));
}

export async function matchesVerifier(
  pepper: string,
  kind: "auth" | "recovery",
  key: string,
  stored: string,
): Promise<boolean> {
  const expected = base64urlDecode(await verifierFor(pepper, kind, key));
  const actual = base64urlDecode(stored);
  return !!expected && !!actual && timingSafeEqual(expected, actual);
}

/** Stable decoy salts for unknown emails, so prelogin doesn't reveal who has an account. */
export async function decoySalt(pepper: string, kind: string, emailAddress: string) {
  const mac = await hmacWithSecret(pepper, `lakhas/decoy-salt/v1:${kind}:${emailAddress}`);
  return base64urlEncode(mac.slice(0, 16));
}

/** Failed sign-ins: 5 free tries, then 1, 2, 4… minutes, capped at an hour. */
export function lockoutUntil(failures: number, now: number): number | null {
  if (failures < 5) return null;
  const minutes = Math.min(60, 2 ** (failures - 5));
  return now + minutes * 60 * 1000;
}
