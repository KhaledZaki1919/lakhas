import { Hono } from "hono";
import { ApiError, errorBody, langOf } from "../lib/errors";
import { LIMITS, bodyLimit, ipRateLimit } from "../lib/limits";
import { log } from "../lib/log";
import type { ApiEnv } from "../types";
import { account } from "./account";
import { auth } from "./auth";
import { pages } from "./pages";

const NONCE_TTL_MS = 10 * 60 * 1000;
const USAGE_KEEP_DAYS = 35;

/**
 * `lakhas-api` (ADR-027): the app's API and the public pages. No admin routes here; the admin
 * panel is the separate `lakhas-admin` Worker behind Cloudflare Access. Never calls AI providers.
 */
const app = new Hono<ApiEnv>();

app.get("/health", (c) => c.json({ ok: true, version: c.env.APP_VERSION }));

app.use(
  "/privacy",
  ipRateLimit((env) => env.PUBLIC_LIMITER),
);
app.use(
  "/terms",
  ipRateLimit((env) => env.PUBLIC_LIMITER),
);
app.route("/", pages);

app.use("/v1/*", bodyLimit(LIMITS.jsonBodyBytes));
app.route("/v1/auth", auth);
app.route("/v1/account", account);

app.notFound((c) => c.json(errorBody("not_found", langOf(c)), 404));

app.onError((err, c) => {
  if (err instanceof ApiError)
    return c.json(errorBody(err.code, langOf(c), err.details), err.status);
  log("error", "unhandled_error", { path: new URL(c.req.url).pathname, message: err.message });
  return c.json(errorBody("internal", langOf(c)), 500);
});

/** Every 10 minutes: drop old nonces, expired refresh tokens and tickets, old usage counters. */
export async function scheduled(_controller: ScheduledController, env: Env): Promise<void> {
  const now = Date.now();
  const oldDay = new Date(now - USAGE_KEEP_DAYS * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM request_nonces WHERE created_at < ?").bind(now - NONCE_TTL_MS),
    env.DB.prepare("DELETE FROM refresh_tokens WHERE expires_at < ?").bind(now),
    env.DB.prepare("DELETE FROM recovery_tickets WHERE expires_at < ?").bind(now),
    env.DB.prepare("DELETE FROM daily_usage WHERE day < ?").bind(oldDay),
  ]);
}

export { app };

export default {
  fetch: app.fetch,
  scheduled,
} satisfies ExportedHandler<Env>;
