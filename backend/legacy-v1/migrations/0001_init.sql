-- Lakhas initial schema (docs/architecture.md §4). Timestamps are Unix ms integers.

-- devices and auth (ADR-013)
CREATE TABLE devices (
  token_id       TEXT PRIMARY KEY,
  label          TEXT NOT NULL,
  secret_enc     TEXT,                 -- base64url AES-GCM ciphertext under TOKEN_ENC_KEY; NULL once revoked
  secret_iv      TEXT,                 -- base64url 96-bit IV
  status         TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  created_at     INTEGER NOT NULL,
  activated_at   INTEGER,
  last_seen_at   INTEGER,
  revoked_at     INTEGER,
  tz             TEXT,
  tz_changed_at  INTEGER,
  lang           TEXT CHECK (lang IN ('ar', 'en')),
  improve_opt_in INTEGER NOT NULL DEFAULT 0,
  cap_overrides  TEXT                  -- JSON, e.g. {"photo": 20}
);

CREATE TABLE request_nonces (
  token_id   TEXT NOT NULL,
  nonce      TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (token_id, nonce)
);
CREATE INDEX idx_request_nonces_created ON request_nonces (created_at);

-- cost caps (ADR-004, ADR-015)
CREATE TABLE cap_events (
  device_id  TEXT NOT NULL,
  day_key    TEXT NOT NULL,
  cap_type   TEXT NOT NULL CHECK (cap_type IN ('photo', 'text', 'recipe', 'barcode', 'correct')),
  input_hash TEXT NOT NULL,
  status     TEXT NOT NULL CHECK (status IN ('reserved', 'committed')),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (device_id, day_key, cap_type, input_hash)
);

CREATE TABLE config (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,            -- JSON
  updated_at INTEGER NOT NULL
);
INSERT INTO config (key, value, updated_at) VALUES
  ('caps', '{"photo":10,"recipe":5,"text":5,"barcode":10,"correct":10,"global":40}', 0),
  ('models', '{"standard":"claude-haiku-5-5","advanced":"claude-sonnet-5-5"}', 0),
  ('retention_days', '30', 0),
  ('db_override_min_confidence', '0.6', 0);

-- food data (the FTS5 index is added with the seed in Phase 4)
CREATE TABLE foods (
  id             TEXT PRIMARY KEY,
  name_en        TEXT NOT NULL,
  name_ar        TEXT NOT NULL,
  name_ar_source TEXT NOT NULL DEFAULT 'human' CHECK (name_ar_source IN ('human', 'machine_translated')),
  aliases_en     TEXT,
  aliases_ar     TEXT,
  kcal_100       REAL NOT NULL,
  protein_100    REAL NOT NULL,
  carbs_100      REAL NOT NULL,
  fat_100        REAL NOT NULL,
  fiber_100      REAL,
  portions       TEXT,                 -- JSON [{label_ar, label_en, grams}]
  source         TEXT NOT NULL CHECK (source IN ('usda', 'curated_estimate', 'curated_verified')),
  source_ref     TEXT,
  notes          TEXT
);

CREATE TABLE products (
  barcode               TEXT PRIMARY KEY,
  name_ar               TEXT,
  name_en               TEXT,
  brand                 TEXT,
  serving_g             REAL,
  kcal_100              REAL NOT NULL,
  protein_100           REAL NOT NULL,
  carbs_100             REAL NOT NULL,
  fat_100               REAL NOT NULL,
  status                TEXT NOT NULL CHECK (status IN ('approved', 'pending_review', 'rejected')),
  origin                TEXT NOT NULL CHECK (origin IN ('off', 'contributed')),
  contributor_device_id TEXT,
  label_image_key       TEXT,
  front_image_key       TEXT,
  illustration_key      TEXT,
  created_at            INTEGER NOT NULL,
  reviewed_at           INTEGER
);
CREATE INDEX idx_products_status ON products (status);

CREATE TABLE portion_corrections (
  food_key    TEXT NOT NULL,
  predicted_g REAL NOT NULL,
  corrected_g REAL NOT NULL,
  created_at  INTEGER NOT NULL
);

-- explore
CREATE TABLE explore_dishes (
  id          TEXT PRIMARY KEY,
  title_ar    TEXT NOT NULL,
  title_en    TEXT NOT NULL,
  desc_ar     TEXT,
  desc_en     TEXT,
  photo_key   TEXT,
  goal_tag    TEXT NOT NULL CHECK (goal_tag IN ('lose', 'maintain', 'gain')),
  meal_types  TEXT NOT NULL,           -- JSON array
  ingredients TEXT NOT NULL,           -- JSON
  kcal        REAL NOT NULL,
  protein     REAL NOT NULL,
  carbs       REAL NOT NULL,
  fat         REAL NOT NULL,
  servings    INTEGER NOT NULL DEFAULT 1,
  published   INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  up_count    INTEGER NOT NULL DEFAULT 0,
  down_count  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE explore_votes (
  dish_id    TEXT NOT NULL,
  device_id  TEXT NOT NULL,
  vote       INTEGER NOT NULL CHECK (vote IN (-1, 1)),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (dish_id, device_id)
);

-- storage and ops
CREATE TABLE uploads (
  r2_key     TEXT PRIMARY KEY,
  device_id  TEXT NOT NULL,
  kind       TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER,
  keep       INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_uploads_expires ON uploads (expires_at);

CREATE TABLE abuse_events (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id  TEXT,
  ip_hash    TEXT,
  kind       TEXT NOT NULL,
  detail     TEXT,
  created_at INTEGER NOT NULL
);

CREATE TABLE admin_audit (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  actor      TEXT NOT NULL,
  action     TEXT NOT NULL,
  target     TEXT,
  created_at INTEGER NOT NULL
);
