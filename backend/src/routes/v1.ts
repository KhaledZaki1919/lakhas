import { Hono } from "hono";
import { ApiError } from "../lib/errors";

/**
 * Versioned API. Every route here will sit behind the device-token middleware (Phase 2).
 * Until a route is implemented it answers 501 with the standard error envelope.
 */
export const v1 = new Hono<{ Bindings: Env }>();

const planned: Array<[method: "get" | "post" | "delete", path: string]> = [
  ["get", "/device"],
  ["delete", "/device"],
  ["post", "/analyze/photo"],
  ["post", "/analyze/text"],
  ["post", "/analyze/correct"],
  ["get", "/barcode/:code"],
  ["post", "/products/contribute"],
  ["post", "/recipes/import-link"],
  ["post", "/recipes/import-image"],
  ["get", "/foods/search"],
  ["get", "/explore"],
  ["post", "/explore/:id/vote"],
  ["get", "/quota"],
];

for (const [method, path] of planned) {
  v1[method](path, () => {
    throw new ApiError("not_implemented", 501);
  });
}
