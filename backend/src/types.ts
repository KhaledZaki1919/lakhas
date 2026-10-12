import type { DeviceRow } from "./db/devices";

/** Hono environment shared by every route. */
export type AppEnv = {
  Bindings: Env;
  Variables: {
    /** Set by deviceAuth on /v1 routes. */
    device: DeviceRow;
    /** Set by accessAuth on /admin routes. */
    adminEmail: string;
  };
};
