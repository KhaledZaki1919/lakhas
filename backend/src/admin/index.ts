import { Hono } from "hono";
import { accessAuth } from "../auth/access";
import { ApiError, errorBody } from "../lib/errors";
import { LIMITS, bodyLimit } from "../lib/limits";
import { log } from "../lib/log";
import type { AdminEnv } from "../types";
import { adminApi } from "./api";
import { ADMIN_HTML, ADMIN_JS } from "./page";

/**
 * `lakhas-admin` (ADR-027 §7): the admin panel. Its whole workers.dev hostname is behind
 * Cloudflare Access, and every request is checked again here (Access JWT), so a disabled or
 * misconfigured Access app fails closed. Shares D1 with `lakhas-api`.
 */
const app = new Hono<AdminEnv>();

app.use("*", accessAuth);
app.use("*", async (c, next) => {
  await next();
  c.header("X-Frame-Options", "DENY");
  c.header("Referrer-Policy", "no-referrer");
  c.header("Cache-Control", "no-store");
});

app.get("/", (c) => {
  c.header(
    "Content-Security-Policy",
    "default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'",
  );
  return c.html(ADMIN_HTML);
});

app.get("/app.js", (c) =>
  c.body(ADMIN_JS, 200, { "Content-Type": "text/javascript; charset=utf-8" }),
);

app.get("/api/me", (c) => c.json({ email: c.var.adminEmail }));
app.use("/api/*", bodyLimit(LIMITS.jsonBodyBytes));
app.route("/api", adminApi);

app.notFound((c) => c.json(errorBody("not_found", "en"), 404));

app.onError((err, c) => {
  if (err instanceof ApiError) return c.json(errorBody(err.code, "en", err.details), err.status);
  log("error", "admin_unhandled_error", {
    path: new URL(c.req.url).pathname,
    message: err.message,
  });
  return c.json(errorBody("internal", "en"), 500);
});

export { app };

export default { fetch: app.fetch } satisfies ExportedHandler<Env>;
