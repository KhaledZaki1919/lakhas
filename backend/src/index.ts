import { Hono } from "hono";
import { ApiError, errorBody, errorResponse, langOf } from "./lib/errors";
import { log } from "./lib/log";
import { v1 } from "./routes/v1";

const app = new Hono<{ Bindings: Env }>();

app.get("/health", (c) => c.json({ ok: true, version: c.env.APP_VERSION }));

app.route("/v1", v1);

app.notFound((c) => c.json(errorBody("not_found", langOf(c)), 404));

app.onError((err, c) => {
  if (err instanceof ApiError) return errorResponse(c, err);
  log("error", "unhandled_error", { path: c.req.path, message: err.message });
  return c.json(errorBody("internal", langOf(c)), 500);
});

async function scheduled(controller: ScheduledController, env: Env): Promise<void> {
  // Phase 2: purge request_nonces (> 10 min) and stale cap reservations.
  // Phase 4: expire meal photos past retention.
  log("info", "cron_tick", { cron: controller.cron, environment: env.ENVIRONMENT });
}

export default {
  fetch: app.fetch,
  scheduled,
} satisfies ExportedHandler<Env>;
