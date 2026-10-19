-- Lakhas D1 schema v2 (ADR-027): accounts, devices, sessions, invites, guards, audit.
-- Timestamps are Unix ms integers. IDs and binary values are base64url text.
-- Later phases add Explore (11) and shared products (12); backups live in the separate
-- database `lakhas_backups` (Phase 10).

CREATE TABLE users (
  id                TEXT PRIMARY KEY,
  email             TEXT NOT NULL UNIQUE,          -- trimmed, lowercased
  email_verified_at INTEGER,                        -- null until email verification exists
  status            TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  share_products    INTEGER NOT NULL DEFAULT 1,     -- ADR-027 §5: on by default
  failed_logins     INTEGER NOT NULL DEFAULT 0,
  locked_until      INTEGER,
  invite_code       TEXT,
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL
);

-- How a user signs in. 'password' now; 'apple' / 'google' later (Sign in with Apple ready).
CREATE TABLE identities (
  provider         TEXT NOT NULL CHECK (provider IN ('password', 'apple', 'google')),
  subject          TEXT NOT NULL,                  -- password: the user id; apple/google: their `sub`
  user_id          TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  email            TEXT,
  is_private_relay INTEGER NOT NULL DEFAULT 0,
  created_at       INTEGER NOT NULL,
  PRIMARY KEY (provider, subject)
);
CREATE INDEX idx_identities_user ON identities (user_id);

-- The password never reaches the server: only HMAC(PEPPER, authKey) is stored (ADR-027 §1).
CREATE TABLE password_credentials (
  user_id    TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  kdf        TEXT NOT NULL CHECK (kdf IN ('pbkdf2-sha256')),
  iterations INTEGER NOT NULL,
  kdf_salt   TEXT NOT NULL,
  auth_salt  TEXT NOT NULL,
  enc_salt   TEXT NOT NULL,
  verifier   TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE recovery_credentials (
  user_id         TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  salt            TEXT NOT NULL,
  verifier        TEXT NOT NULL,                   -- HMAC(PEPPER, recoveryAuth)
  failed_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until    INTEGER,
  updated_at      INTEGER NOT NULL
);

-- The backup data key, only ever wrapped on the phone (AES-GCM). The server can't unwrap it.
CREATE TABLE key_envelopes (
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK (kind IN ('password', 'recovery', 'passphrase')),
  version    INTEGER NOT NULL DEFAULT 1,
  nonce      TEXT NOT NULL,
  wrapped    TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, kind)
);

CREATE TABLE devices (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  label        TEXT NOT NULL,
  platform     TEXT NOT NULL,
  app_version  TEXT,
  secret_enc   TEXT,                               -- AES-GCM under DEVICE_ENC_KEY; null once revoked
  secret_iv    TEXT,
  status       TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER,
  revoked_at   INTEGER
);
CREATE INDEX idx_devices_user ON devices (user_id);

CREATE TABLE refresh_tokens (
  token_hash TEXT PRIMARY KEY,                     -- SHA-256 hex of the token
  device_id  TEXT NOT NULL REFERENCES devices (id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL,
  used_at    INTEGER,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_refresh_tokens_device ON refresh_tokens (device_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens (expires_at);

CREATE TABLE request_nonces (
  device_id  TEXT NOT NULL,
  nonce      TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (device_id, nonce)
);
CREATE INDEX idx_request_nonces_created ON request_nonces (created_at);

-- Short-lived ticket between "prove the recovery code" and "set a new password".
CREATE TABLE recovery_tickets (
  ticket_hash TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  expires_at  INTEGER NOT NULL,
  used_at     INTEGER
);

CREATE TABLE invites (
  code       TEXT PRIMARY KEY,                     -- uppercase
  active     INTEGER NOT NULL DEFAULT 1,
  max_uses   INTEGER,
  uses       INTEGER NOT NULL DEFAULT 0,
  expires_at INTEGER,
  created_at INTEGER NOT NULL
);

-- Free-tier guards (ADR-027 §11).
CREATE TABLE daily_usage (
  day      TEXT NOT NULL,
  resource TEXT NOT NULL,
  count    INTEGER NOT NULL,
  PRIMARY KEY (day, resource)
);

CREATE TABLE abuse_events (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  kind       TEXT NOT NULL,
  ip_hash    TEXT,
  user_id    TEXT,
  detail     TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_abuse_events_created ON abuse_events (created_at);

CREATE TABLE admin_audit (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  actor      TEXT NOT NULL,                        -- admin email, or 'user' / 'system'
  action     TEXT NOT NULL,
  target     TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_admin_audit_created ON admin_audit (created_at);
