import { generateKeyPairSync, randomBytes } from "node:crypto";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// Throwaway keys for the test run: an RSA key standing in for Cloudflare Access, and random
// Worker secrets. Never used outside tests.
const { publicKey, privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const publicJwk = {
  ...publicKey.export({ format: "jwk" }),
  kid: "test-key",
  alg: "RS256",
  use: "sig",
};
const privateJwk = { ...privateKey.export({ format: "jwk" }), kid: "test-key", alg: "RS256" };
const secret = () => randomBytes(32).toString("base64url");

export default defineConfig(async () => {
  const migrations = await readD1Migrations("./migrations");
  return {
    plugins: [
      cloudflareTest({
        // Both Workers share these bindings; the admin app is exercised through `app.request`.
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            ENVIRONMENT: "test",
            PEPPER: secret(),
            DEVICE_ENC_KEY: secret(),
            ACCESS_TOKEN_KEY: secret(),
            LOG_HASH_KEY: secret(),
            ACCESS_TEAM_DOMAIN: "lakhas-test.cloudflareaccess.com",
            ACCESS_AUD: "test-aud",
            ACCESS_TEST_JWKS: JSON.stringify({ keys: [publicJwk] }),
            TEST_ACCESS_PRIVATE_JWK: JSON.stringify(privateJwk),
          },
        },
      }),
    ],
    test: { include: ["test/**/*.test.ts"], setupFiles: ["./test/apply-migrations.ts"] },
  };
});
