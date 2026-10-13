# FROZEN — not built, not deployed (ADR-020)

Lakhas became Bring-Your-Own-Key on 2026-10-13: the iOS app calls AI providers directly with the user's own key, and there is no server. This Cloudflare Worker (device tokens, HMAC signing, caps, admin API) is kept for reference only.

- Its CI workflow (`.github/workflows/backend.yml`) runs only when triggered manually.
- Some tests reference files that moved to `shared/frozen/` (`signing.json`). Update the import paths if you ever revive it.
- Don't add features here.
