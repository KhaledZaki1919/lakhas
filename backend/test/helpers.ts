import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { app as adminApp } from "../src/admin";
import { app as apiApp } from "../src/api";
import { sign } from "../src/auth/signing";
import { base64urlDecode, base64urlEncode, randomBytes } from "../src/lib/crypto";
import type { SessionResponse } from "../src/services/sessions";

const API = "https://lakhas-api.test";
const ADMIN = "https://lakhas-admin.test";
const encoder = new TextEncoder();

/** A fresh client IP per call, so the per-IP auth limit doesn't trip across tests. */
export function freshIp(): string {
  const b = randomBytes(4);
  return `10.${b[0]}.${b[1]}.${b[2]}`;
}

export async function apiFetch(path: string, init: RequestInit = {}, ip = freshIp()) {
  const headers = new Headers(init.headers);
  if (!headers.has("CF-Connecting-IP")) headers.set("CF-Connecting-IP", ip);
  if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  const ctx = createExecutionContext();
  const res = await apiApp.request(`${API}${path}`, { ...init, headers }, env, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

export function postJson(path: string, payload: unknown, ip?: string) {
  return apiFetch(path, { method: "POST", body: JSON.stringify(payload) }, ip);
}

/** Mints a Cloudflare Access JWT signed with the test RSA key. */
export async function accessJwt(
  claims: Partial<{ aud: string; iss: string; exp: number; email: string }> = {},
): Promise<string> {
  const jwk = JSON.parse(env.TEST_ACCESS_PRIVATE_JWK) as JsonWebKey;
  const key = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const header = base64urlEncode(encoder.encode(JSON.stringify({ alg: "RS256", kid: "test-key" })));
  const payload = base64urlEncode(
    encoder.encode(
      JSON.stringify({
        aud: [env.ACCESS_AUD],
        iss: `https://${env.ACCESS_TEAM_DOMAIN}`,
        exp: Math.floor(Date.now() / 1000) + 300,
        email: "admin@example.com",
        ...claims,
      }),
    ),
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(`${header}.${payload}`),
  );
  return `${header}.${payload}.${base64urlEncode(signature)}`;
}

export async function adminFetch(path: string, init: RequestInit = {}, jwt?: string | null) {
  const headers = new Headers(init.headers);
  if (jwt !== null) headers.set("Cf-Access-Jwt-Assertion", jwt ?? (await accessJwt()));
  if (init.method && init.method !== "GET") {
    if (!headers.has("X-Lakhas-Admin")) headers.set("X-Lakhas-Admin", "1");
    if (!headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  }
  const ctx = createExecutionContext();
  const res = await adminApp.request(`${ADMIN}${path}`, { ...init, headers }, env, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

export async function createInvite(code?: string, extra: Record<string, unknown> = {}) {
  const res = await adminFetch("/api/invites", {
    method: "POST",
    body: JSON.stringify({ ...(code ? { code } : {}), ...extra }),
  });
  if (res.status !== 201) throw new Error(`invite failed: ${res.status} ${await res.text()}`);
  return ((await res.json()) as { code: string }).code;
}

const key = () => base64urlEncode(randomBytes(32));
const salt16 = () => base64urlEncode(randomBytes(16));
const box = () => ({
  nonce: base64urlEncode(randomBytes(12)),
  wrapped: base64urlEncode(randomBytes(48)),
});

/**
 * What the phone sends at sign up. The server can't tell these random keys from real HKDF
 * outputs; the real derivation is covered by shared/test-vectors/account-keys.json.
 */
export function signupMaterial(
  inviteCode: string,
  email = `user${Date.now()}${Math.random()}@example.com`,
) {
  return {
    inviteCode,
    email,
    authKey: key(),
    kdf: { name: "pbkdf2-sha256", iterations: 600_000 },
    salts: { kdf: salt16(), auth: salt16(), enc: salt16() },
    recovery: { salt: salt16(), authKey: key() },
    envelopes: { password: box(), recovery: box() },
    device: { label: "Test iPhone", platform: "ios", appVersion: "0.2.0" },
  };
}

export type Material = ReturnType<typeof signupMaterial>;

export interface TestAccount {
  material: Material;
  userId: string;
  session: SessionResponse;
}

export async function signUp(inviteCode?: string): Promise<TestAccount> {
  const material = signupMaterial(inviteCode ?? (await createInvite()));
  const res = await postJson("/v1/auth/signup", material);
  if (res.status !== 201) throw new Error(`signup failed: ${res.status} ${await res.text()}`);
  const data = (await res.json()) as { user: { id: string }; session: SessionResponse };
  return { material, userId: data.user.id, session: data.session };
}

export interface SignedOptions {
  method?: string;
  body?: unknown;
  timestamp?: number;
  nonce?: string;
  accessToken?: string | null;
  tamper?: boolean;
}

/** A request signed like the phone does (LK2), with the session's access token. */
export async function signed(session: SessionResponse, path: string, options: SignedOptions = {}) {
  const method = options.method ?? "GET";
  const body = options.body === undefined ? "" : JSON.stringify(options.body);
  const timestamp = String(options.timestamp ?? Date.now());
  const nonce = options.nonce ?? base64urlEncode(randomBytes(16));
  const secret = base64urlDecode(session.deviceSecret);
  if (!secret) throw new Error("bad device secret");
  const signature = await sign(secret, {
    method,
    pathAndQuery: path,
    timestamp,
    nonce,
    deviceId: session.deviceId,
    body,
  });
  const headers: Record<string, string> = {
    "X-Lakhas-Device": session.deviceId,
    "X-Lakhas-Timestamp": timestamp,
    "X-Lakhas-Nonce": nonce,
    "X-Lakhas-Signature": signature,
  };
  const token = options.accessToken === undefined ? session.accessToken : options.accessToken;
  if (token) headers.Authorization = `Bearer ${token}`;
  return apiFetch(path, {
    method,
    headers,
    ...(method === "GET" ? {} : { body: options.tamper ? `${body} ` : body }),
  });
}

export async function errorCode(res: Response): Promise<string | undefined> {
  const data = (await res.json()) as { error?: { code?: string } };
  return data.error?.code;
}
