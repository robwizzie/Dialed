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

-- v3: weekly side bets. Each side writes only its own score.
CREATE TABLE IF NOT EXISTS bets (
  id TEXT PRIMARY KEY,
  challenge_id TEXT NOT NULL,
  week TEXT NOT NULL,
  metric TEXT NOT NULL,
  stake TEXT NOT NULL,
  proposer TEXT NOT NULL CHECK (proposer IN ('owner','friend')),
  status TEXT NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed','active','declined','cancelled')),
  owner_score REAL,
  friend_score REAL,
  paid INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS bets_by_challenge ON bets (challenge_id, week);

-- v4: each side's latest weekly report (the Sunday summary), shown on the other side's page.
CREATE TABLE IF NOT EXISTS reports (
  challenge_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('owner','friend')),
  week TEXT NOT NULL,
  json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (challenge_id, role)
);

-- v5: restaurant menus for food logging, cached per chain (food.js).
CREATE TABLE IF NOT EXISTS menus (
  chain_key TEXT PRIMARY KEY,
  json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
