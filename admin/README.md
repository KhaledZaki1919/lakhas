# Admin UI

Minimal admin panel served by the `lakhas-api` Worker under `/admin`, protected by Cloudflare Access (ADR-007).

- **Phase 2:** device tokens (create with QR code, label, per-device caps, revoke).
- **Phase 7:** Explore CRUD, contributed-product review queue, machine-translation review queue, config editing.

Static assets in this folder are bundled into the Worker at build time.

> **FROZEN (ADR-020):** there is no server and no admin panel. Kept for reference only.
