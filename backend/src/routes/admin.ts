import { Hono } from "hono";
import { renderSVG } from "uqr";
import { z } from "zod";
import { accessAuth } from "../auth/access";
import { formatToken } from "../auth/signing";
import { insertDevice, listDevices, revokeDevice, updateDevice } from "../db/devices";
import { base64urlEncode, encryptSecret, randomBytes } from "../lib/crypto";
import { ApiError } from "../lib/errors";
import { log } from "../lib/log";
import type { AppEnv } from "../types";
import { ADMIN_PAGE } from "./admin-page";

/** Admin panel + JSON API behind Cloudflare Access (ADR-007). Phase 2: device tokens. */
export const admin = new Hono<AppEnv>();

admin.use("*", accessAuth);

const capCount = z.number().int().min(0).max(1000);
const capOverrides = z
  .object({
    photo: capCount,
    text: capCount,
    recipe: capCount,
    barcode: capCount,
    correct: capCount,
    global: capCount,
  })
  .partial()
  .strict();

const createBody = z.object({ label: z.string().trim().min(1).max(60) }).strict();
const patchBody = z
  .object({
    label: z.string().trim().min(1).max(60).optional(),
    capOverrides: capOverrides.nullable().optional(),
  })
  .strict();

async function parse<T extends z.ZodType>(schema: T, req: Request): Promise<z.infer<T>> {
  const result = schema.safeParse(await req.json().catch(() => undefined));
  if (!result.success) throw new ApiError("invalid_request", 400);
  return result.data;
}

async function audit(db: D1Database, actor: string, action: string, target: string) {
  await db
    .prepare("INSERT INTO admin_audit (actor, action, target, created_at) VALUES (?, ?, ?, ?)")
    .bind(actor, action, target, Date.now())
    .run();
}

const ALPHANUMERIC = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
function newTokenId(): string {
  return [...randomBytes(16)].map((b) => ALPHANUMERIC[b % ALPHANUMERIC.length]).join("");
}

admin.get("/", (c) => c.html(ADMIN_PAGE));

admin.get("/api/devices", async (c) => c.json({ items: await listDevices(c.env.DB) }));

/** Creates a device token. The full token is returned once and never stored in clear. */
admin.post("/api/devices", async (c) => {
  const { label } = await parse(createBody, c.req.raw);
  const tokenId = newTokenId();
  const secret = randomBytes(32);
  const { ciphertext, iv } = await encryptSecret(c.env.TOKEN_ENC_KEY, secret);
  await insertDevice(c.env.DB, {
    tokenId,
    label,
    secretEnc: base64urlEncode(ciphertext),
    secretIv: base64urlEncode(iv),
    now: Date.now(),
  });
  await audit(c.env.DB, c.get("adminEmail"), "device.create", tokenId);
  log("info", "device_created", { device: tokenId.slice(0, 4) });

  const token = formatToken(tokenId, secret);
  return c.json({ tokenId, label, token, qrSvg: renderSVG(token, { border: 2 }) }, 201);
});

admin.patch("/api/devices/:id", async (c) => {
  const body = await parse(patchBody, c.req.raw);
  const found = await updateDevice(c.env.DB, c.req.param("id"), {
    label: body.label,
    capOverrides: body.capOverrides,
  });
  if (!found) throw new ApiError("not_found", 404);
  await audit(c.env.DB, c.get("adminEmail"), "device.update", c.req.param("id"));
  return c.body(null, 204);
});

admin.post("/api/devices/:id/revoke", async (c) => {
  const revoked = await revokeDevice(c.env.DB, c.req.param("id"), Date.now());
  if (!revoked) throw new ApiError("not_found", 404);
  await audit(c.env.DB, c.get("adminEmail"), "device.revoke", c.req.param("id"));
  return c.body(null, 204);
});
