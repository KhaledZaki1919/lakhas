import { Hono } from "hono";
import { ApiError, errorBody, errorResponse, langOf } from "./lib/errors";
import { log } from "./lib/log";
import { admin } from "./routes/admin";
import { v1 } from "./routes/v1";
import { purgeStaleReservations } from "./services/caps";
import type { AppEnv } from "./types";

const NONCE_TTL_MS = 10 * 60 * 1000;

const app = new Hono<AppEnv>();

app.get("/health", (c) => c.json({ ok: true, version: c.env.APP_VERSION }));

app.route("/v1", v1);
app.route("/admin", admin);

app.notFound((c) => c.json(errorBody("not_found", langOf(c)), 404));

app.onError((err, c) => {
  if (err instanceof ApiError) return errorResponse(c, err);
  log("error", "unhandled_error", { path: c.req.path, message: err.message });
  return c.json(errorBody("internal", langOf(c)), 500);
});

async function scheduled(controller: ScheduledController, env: Env): Promise<void> {
  const now = Date.now();
  await env.DB.prepare("DELETE FROM request_nonces WHERE created_at < ?")
    .bind(now - NONCE_TTL_MS)
    .run();
  await purgeStaleReservations(env.DB, now);
  // Phase 4: expire meal photos past retention.
  log("info", "cron_done", { cron: controller.cron });
}

export default {
  fetch: app.fetch,
  scheduled,
} satisfies ExportedHandler<Env>;
