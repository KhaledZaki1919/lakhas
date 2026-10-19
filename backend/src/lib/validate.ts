import type { Context } from "hono";
import type { z } from "zod";
import { ApiError } from "./errors";

/** Parses the JSON body against `schema`; anything else is `invalid_request` (400). */
export async function body<T extends z.ZodType>(c: Context, schema: T): Promise<z.infer<T>> {
  let raw: unknown;
  try {
    raw = await c.req.json();
  } catch {
    throw new ApiError("invalid_request", 400);
  }
  const result = schema.safeParse(raw);
  if (!result.success) {
    throw new ApiError("invalid_request", 400, {
      fields: result.error.issues.map((issue) => issue.path.join(".")).slice(0, 10),
    });
  }
  return result.data;
}
