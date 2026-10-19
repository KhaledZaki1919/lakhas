import type { DeviceWithUser } from "./db/accounts";

/** Hono environment of the API Worker (`lakhas-api`). */
export type ApiEnv = {
  Bindings: Env;
  Variables: {
    /** Set by `signedDevice` / `session` on signed routes. */
    device: DeviceWithUser;
  };
};

/** Hono environment of the admin Worker (`lakhas-admin`). */
export type AdminEnv = {
  Bindings: Env;
  Variables: {
    /** Set by `accessAuth`: the Cloudflare Access user. */
    adminEmail: string;
  };
};
