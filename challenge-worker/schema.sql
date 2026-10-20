-- Already applied to the dialed-challenge D1 database.
-- Re-apply with: npx wrangler d1 execute dialed-challenge --remote --file schema.sql
CREATE TABLE IF NOT EXISTS challenges (
  id TEXT PRIMARY KEY,
  owner_name TEXT NOT NULL,
  friend_name TEXT NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  owner_token_hash TEXT NOT NULL,
  friend_token_hash TEXT NOT NULL,
  owner_start REAL,
  friend_start REAL,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS weighins (
  challenge_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('owner','friend')),
  date TEXT NOT NULL,
  pounds REAL NOT NULL,
  updated_at TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'manual',
  PRIMARY KEY (challenge_id, role, date)
);
CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  challenge_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('owner','friend')),
  text TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS messages_by_challenge ON messages (challenge_id, id);

-- v2: where a weigh-in came from, and each side's stats card.
-- (source column is in the CREATE above; existing DBs: ALTER TABLE weighins ADD COLUMN source TEXT NOT NULL DEFAULT 'manual';)
CREATE TABLE IF NOT EXISTS stats (
  challenge_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('owner','friend')),
  json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (challenge_id, role)
);
