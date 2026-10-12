import { generateKeyPairSync, randomBytes } from "node:crypto";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// Throwaway keys for the test run: an RSA key standing in for Cloudflare Access, and an
// AES key for token secrets. Never used outside tests.
const { publicKey, privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const publicJwk = {
  ...publicKey.export({ format: "jwk" }),
  kid: "test-key",
  alg: "RS256",
  use: "sig",
};
const privateJwk = { ...privateKey.export({ format: "jwk" }), kid: "test-key", alg: "RS256" };

export default defineConfig(async () => {
  const migrations = await readD1Migrations("./migrations");
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            ENVIRONMENT: "test",
            TOKEN_ENC_KEY: randomBytes(32).toString("base64"),
            ACCESS_TEAM_DOMAIN: "lakhas-test.cloudflareaccess.com",
            ACCESS_AUD: "test-aud",
            ACCESS_TEST_JWKS: JSON.stringify({ keys: [publicJwk] }),
            TEST_ACCESS_PRIVATE_JWK: JSON.stringify(privateJwk),
          },
        },
      }),
    ],
    test: { setupFiles: ["./test/apply-migrations.ts"] },
  };
});
