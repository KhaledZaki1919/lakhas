import { SELF } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { parseToken, sign } from "../src/auth/signing";
import { base64urlEncode, randomBytes } from "../src/lib/crypto";

const BASE = "https://api.test";
const encoder = new TextEncoder();

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

export async function adminFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set("Cf-Access-Jwt-Assertion", await accessJwt());
  return SELF.fetch(`${BASE}${path}`, { ...init, headers });
}

export async function createDevice(label = "Test iPhone"): Promise<string> {
  const res = await adminFetch("/admin/api/devices", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ label }),
  });
  if (res.status !== 201) throw new Error(`create device failed: ${res.status}`);
  return ((await res.json()) as { token: string }).token;
}

export interface SignedOptions {
  method?: string;
  body?: string;
  timestamp?: number;
  nonce?: string;
  headers?: Record<string, string>;
  tamper?: (signature: string) => string;
}

/** Sends a request signed exactly like the iOS client (ADR-013). */
export async function signedFetch(
  token: string,
  pathAndQuery: string,
  opts: SignedOptions = {},
): Promise<Response> {
  const parsed = parseToken(token);
  if (!parsed) throw new Error("bad token");
  const method = opts.method ?? "GET";
  const body = opts.body ?? "";
  const timestamp = String(opts.timestamp ?? Date.now());
  const nonce = opts.nonce ?? base64urlEncode(randomBytes(16));
  let signature = await sign(parsed.secret, { method, pathAndQuery, timestamp, nonce, body });
  if (opts.tamper) signature = opts.tamper(signature);

  return SELF.fetch(`${BASE}${pathAndQuery}`, {
    method,
    body: method === "GET" || method === "HEAD" ? undefined : body,
    headers: {
      "X-Lakhas-Token-Id": parsed.tokenId,
      "X-Lakhas-Timestamp": timestamp,
      "X-Lakhas-Nonce": nonce,
      "X-Lakhas-Signature": signature,
      "CF-Connecting-IP": `198.51.100.${Math.floor(Math.random() * 250) + 1}`,
      ...opts.headers,
    },
  });
}

export async function errorCode(res: Response): Promise<string> {
  return ((await res.json()) as { error: { code: string } }).error.code;
}

/** Splits lk1_<id>_<secret>; the base64url secret itself may contain "_". */
export function tokenParts(token: string): { id: string; secret: string } {
  const second = token.indexOf("_", 4);
  return { id: token.slice(4, second), secret: token.slice(second + 1) };
}
