# Runbook — certificate pinning (ADR-005)

The app pins the **SPKI SHA-256 hashes of CA root certificates**, not our leaf certificate. Cloudflare rotates edge certificates and keys on its own schedule, and it can issue from Let's Encrypt, Google Trust Services or SSL.com. A request succeeds only when iOS trusts the chain **and** some certificate in it matches a pin (`PinValidator` in LakhasKit). Pins apply to the API host only.

## Current pins (`ios/project.yml` → `LakhasPinnedSPKI`)

| CA root | SPKI SHA-256 (base64) | Root expires |
|---|---|---|
| ISRG Root X1 | `C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=` | 2035-06-04 |
| ISRG Root X2 | `diGVwiVYbubAI3RW4hB9xU8e/CH2GnkuvVFZE8zmgzI=` | 2040-09-17 |
| GTS Root R1 | `hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=` | 2036-06-22 |
| GTS Root R2 | `Vfd95BwDeSQo+NUYxVEEIlvkOlWY2SalKK1lPhzOx78=` | 2036-06-22 |
| GTS Root R3 | `QXnt2YHvdHR3tJYmQIr0Paosp6t/nggsEGD4QJZ3Q0g=` | 2036-06-22 |
| GTS Root R4 | `mEflZT5enoR1FuXLgYYGqnVEoZvmf9c2bVBpiOjYQ0c=` | 2036-06-22 |
| SSL.com TLS RSA Root CA 2022 | `K89VOmb1cJAN3TK6bf4ezAbJGC1mLcG2Dh97dnwr3VQ=` | 2046-08-19 |

Sources (2026-10-12):
- GTS roots: `pki.goog/repo/certs`;
- ISRG X2: Let's Encrypt's website repository;
- ISRG X1 and SSL.com RSA 2022: the Windows trusted root store.

Missing: **SSL.com TLS ECC Root CA 2022**. It couldn't be fetched from this network. Add it before relying on an SSL.com-issued certificate (see "Add a pin" below).

## Our API host
The API runs on the free **workers.dev** subdomain (no custom domain). Its chain on 2026-10-12: `*.workers.dev` → **GTS WE1** → **GTS Root R4** (pinned; also cross-signed by GlobalSign Root CA). The CA for workers.dev can't be chosen, which is why both the Google and Let's Encrypt families stay pinned.

## Compute a pin
```
openssl x509 -in root.pem -noout -pubkey \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary | openssl base64
```

## Check which CA our edge certificate uses
```
openssl s_client -connect <api-domain>:443 -servername <api-domain> -showcerts </dev/null \
  | openssl x509 -noout -issuer
```
In the Cloudflare dashboard, set **SSL/TLS → Edge Certificates → Certificate Authority** to Let's Encrypt or Google if you want to stay within the pinned set.

## Add a pin
1. Compute the new root's pin (above).
2. Add it to `LakhasPinnedSPKI` in `ios/project.yml`, with a comment naming the CA.
3. Push. CI builds a new IPA; install it with Sideloadly **before** the edge certificate changes.

## If a pin breaks (app shows "Couldn't reach the server")
1. Check the issuer (above). If Cloudflare moved to an unpinned CA, switch the CA back in the dashboard (fastest).
2. Otherwise, add the new root's pin and ship a new IPA.

Keep at least two CA families pinned at all times.
