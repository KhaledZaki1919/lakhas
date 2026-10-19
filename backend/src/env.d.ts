// Secrets and per-Worker vars that `wrangler types` can't see (ADR-027).
interface LakhasSecrets {
  /** lakhas-api secret: keys the password and recovery verifiers (HMAC). Losing it locks everyone out. */
  PEPPER: string;
  /** lakhas-api secret: 32 bytes, encrypts device secrets at rest (AES-GCM). */
  DEVICE_ENC_KEY: string;
  /** lakhas-api secret: signs access tokens (HMAC). */
  ACCESS_TOKEN_KEY: string;
  /** lakhas-api secret: keys IP hashes in the abuse log. */
  LOG_HASH_KEY: string;
  /** lakhas-admin var: Cloudflare Access team domain, e.g. "team.cloudflareaccess.com". */
  ACCESS_TEAM_DOMAIN: string;
  /** lakhas-admin var: the Access application's audience (AUD) tag. */
  ACCESS_AUD: string;
  /** Test only (honored when ENVIRONMENT === "test"): JWKS JSON replacing the Access certs fetch. */
  ACCESS_TEST_JWKS?: string;
}

// The generated global `Env` and `Cloudflare.Env` are separate interfaces; extend both.
interface Env extends LakhasSecrets {}
declare namespace Cloudflare {
  interface Env extends LakhasSecrets {}
}
