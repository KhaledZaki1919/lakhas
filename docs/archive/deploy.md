# Runbook — first deploy of `lakhas-api` to Cloudflare

Run these once from `backend/` on Windows (Git Bash, `export PATH="/c/Program Files/nodejs:$PATH"`). They need your Cloudflare account; nothing here is secret except the values you type into `wrangler secret put`.

## 1. Log in
```
npx wrangler login            # opens the browser; approve access to your account
npx wrangler whoami           # shows the account ID
```

## 2. Create the resources and paste their IDs into `wrangler.toml`
```
npx wrangler d1 create lakhas                 # → database_id
npx wrangler kv namespace create CACHE        # → id
npx wrangler r2 bucket create lakhas-media
```
Replace the placeholder `database_id` and KV `id` in `backend/wrangler.toml`, then run `npm run cf-typegen`.

## 3. Apply the schema
```
npx wrangler d1 migrations apply lakhas --remote
```

## 4. Secrets
Generate the token-encryption key locally. It never leaves Cloudflare after this step:
```
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
npx wrangler secret put TOKEN_ENC_KEY         # paste the value above
npx wrangler secret put ANTHROPIC_API_KEY     # Phase 4
```
**Losing `TOKEN_ENC_KEY` invalidates every device token.** Store a copy in your password manager.

## 5. API address: the free workers.dev subdomain
No custom domain is needed. `npx wrangler deploy` prints the URL, e.g. `https://lakhas-api.<account-subdomain>.workers.dev`.
- Set `LAKHAS_API_BASE_URL` in `ios/project.yml` to that URL and push. CI builds a new IPA.
- **Pinning works as shipped.** workers.dev certificates are issued by Google Trust Services (WE1 → GTS Root R4, checked 2026-10-12), and GTS R4 is pinned. You can't pick the CA for workers.dev, but Let's Encrypt is pinned too.
- If you add a custom domain later, keep its CA on Let's Encrypt or Google (see `pinning.md`).

## 6. Cloudflare Access for `/admin`
1. Protect the admin panel on workers.dev: **Workers & Pages → lakhas-api → Settings → Domains & Routes → workers.dev → Enable Cloudflare Access**. Then edit the generated Access application so its path covers `admin`, with a policy: Allow → Emails → your email (one-time PIN login). The `/v1` API must stay outside Access, because the app authenticates with device tokens.
2. Copy the application's **AUD tag**, and note the team domain (`<team>.cloudflareaccess.com`).
3. Store both:
   ```
   npx wrangler secret put ACCESS_AUD
   npx wrangler secret put ACCESS_TEAM_DOMAIN
   ```

## 7. Deploy and smoke-test
```
npx wrangler deploy
curl https://lakhas-api.<account-subdomain>.workers.dev/health          # {"ok":true,...}
```
Open `https://lakhas-api.<account-subdomain>.workers.dev/admin`, log in through Access, create a device token, and enter it in the app.

## 8. Production environment flag
`ENVIRONMENT` is `dev` in `wrangler.toml`. Before relying on the deployment, set it to `production` (test-only code paths check `ENVIRONMENT === "test"` and stay off either way).
