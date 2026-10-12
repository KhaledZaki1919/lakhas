// Secrets and test-only bindings that `wrangler types` can't see (set with `wrangler secret put`).
interface LakhasSecrets {
  /** 32 random bytes, base64: encrypts device-token secrets at rest (ADR-013). */
  TOKEN_ENC_KEY: string;
  /** Cloudflare Access team domain, e.g. "lakhas.cloudflareaccess.com" (ADR-007). */
  ACCESS_TEAM_DOMAIN: string;
  /** Cloudflare Access application audience tag. */
  ACCESS_AUD: string;
  /** Test only (honored when ENVIRONMENT === "test"): JWKS JSON replacing the Access certs fetch. */
  ACCESS_TEST_JWKS?: string;
}

// The generated global `Env` and `Cloudflare.Env` are separate interfaces; extend both.
interface Env extends LakhasSecrets {}
declare namespace Cloudflare {
  interface Env extends LakhasSecrets {}
}
