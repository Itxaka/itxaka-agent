-- kairos-triage-agent audit schema.
--
-- Local SQLite ledger written by the manager on every state transition,
-- role handoff, verdict, artifact, gated call, and cost tick. Both live
-- and dry-run runs write here — the DB is local-only, no external side
-- effect. This is what a dashboard reads.
--
-- The manager runs this file with `sqlite3 <db> < config/audit-schema.sql`
-- at the start of every invocation. All statements are idempotent.

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- One row per manager invocation.
CREATE TABLE IF NOT EXISTS slots (
  slot_id         TEXT PRIMARY KEY,          -- ISO ts + short rand suffix
  seq             INTEGER,                   -- monotonic per-DB counter, assigned on INSERT
  started_at      TEXT NOT NULL,             -- ISO 8601 UTC
  ended_at        TEXT,
  wall_ms         INTEGER,
  dry_run         INTEGER NOT NULL DEFAULT 0,
  ticket_ref      TEXT,                      -- owner/repo#n, null when idle
  entry_reason    TEXT,                      -- 'scheduled' | 'manual' | 'smoke-test'
  outcome         TEXT,                      -- 'finished' | 'error' (idle exits are NOT recorded; ticket-level state lives on the ticket, not the slot)
  progress_note   TEXT,                      -- one-line summary of what this slot advanced, e.g. "coder round 0: 23 commits, envelope at testing"
  gated_calls     INTEGER NOT NULL DEFAULT 0,
  envelope_writes INTEGER NOT NULL DEFAULT 0
);

-- One-shot migration for DBs created before `progress_note` existed.
ALTER TABLE slots ADD COLUMN progress_note TEXT;

-- Migration for databases created before `seq` existed. SQLite has no
-- `ADD COLUMN IF NOT EXISTS`, so this errors cosmetically once the column
-- is in place; sqlite3(1) does not `.bail` on that by default, and the rest
-- of the schema keeps applying. Backfill old rows with
-- `scripts/backfill-slot-seq.py` after the first init on an old DB.
ALTER TABLE slots ADD COLUMN seq INTEGER;

-- Dimension: one row per ticket the fleet has ever touched.
CREATE TABLE IF NOT EXISTS tickets (
  ticket_ref     TEXT PRIMARY KEY,           -- owner/repo#n
  owner          TEXT NOT NULL,
  repo           TEXT NOT NULL,
  number         INTEGER NOT NULL,
  kind           TEXT NOT NULL,              -- 'issue' | 'pr'
  author         TEXT,
  third_party    INTEGER,                    -- 0/1 for PRs; null for issues
  first_seen_at  TEXT NOT NULL,
  last_seen_at   TEXT NOT NULL,
  terminal_phase TEXT                        -- latest phase observed
);

-- Every state transition and role handoff.
CREATE TABLE IF NOT EXISTS events (
  event_id     INTEGER PRIMARY KEY AUTOINCREMENT,
  slot_id      TEXT NOT NULL REFERENCES slots(slot_id),
  ticket_ref   TEXT NOT NULL,
  ts           TEXT NOT NULL,
  phase_before TEXT,
  phase_after  TEXT,
  role         TEXT,                         -- 'manager'|'coder'|'tester'|'docs'|'reviewer', null for pure-manager actions
  action       TEXT NOT NULL,                -- 'intake'|'dispatch'|'return'|'verdict'|'pre_review_collect'|'audit_publish'|'phase_change'|'error'
  wall_ms      INTEGER,
  tokens       INTEGER,
  note         TEXT
);

-- Every reviewer verdict (round-scoped).
CREATE TABLE IF NOT EXISTS verdicts (
  verdict_id    INTEGER PRIMARY KEY AUTOINCREMENT,
  slot_id       TEXT NOT NULL REFERENCES slots(slot_id),
  ticket_ref    TEXT NOT NULL,
  round         INTEGER NOT NULL,
  verdict       TEXT NOT NULL,               -- 'approve' | 'changes-requested'
  comment_count INTEGER NOT NULL DEFAULT 0,
  ts            TEXT NOT NULL
);

-- Every artifact produced (commit, test file, doc file, log, screendump, ISO recipe, PR review).
CREATE TABLE IF NOT EXISTS artifacts (
  artifact_id INTEGER PRIMARY KEY AUTOINCREMENT,
  slot_id     TEXT NOT NULL REFERENCES slots(slot_id),
  ticket_ref  TEXT NOT NULL,
  kind        TEXT NOT NULL,                 -- 'commit'|'test'|'doc'|'log'|'screendump'|'iso_recipe'|'pr_review'|'issue_comment'
  ref         TEXT NOT NULL,                 -- sha, path, or short id
  note        TEXT,
  ts          TEXT NOT NULL
);

-- Cost per role invocation.
CREATE TABLE IF NOT EXISTS costs (
  cost_id    INTEGER PRIMARY KEY AUTOINCREMENT,
  slot_id    TEXT NOT NULL REFERENCES slots(slot_id),
  ticket_ref TEXT NOT NULL,
  role       TEXT NOT NULL,
  tokens     INTEGER NOT NULL,
  usd        REAL NOT NULL DEFAULT 0.0,      -- stays 0.0 until pricing is wired
  ts         TEXT NOT NULL
);

-- Per-finding comments produced by the reviewer, one row per file:line entry
-- of a `changes-requested` verdict. This is what a human wants to read on the
-- ticket page — the actual problems and their suggestions, not just the count.
CREATE TABLE IF NOT EXISTS comments (
  comment_id  INTEGER PRIMARY KEY AUTOINCREMENT,
  slot_id     TEXT NOT NULL REFERENCES slots(slot_id),
  ticket_ref  TEXT NOT NULL,
  round       INTEGER NOT NULL,
  role        TEXT NOT NULL,                 -- who authored the comment; usually 'reviewer'
  file        TEXT,
  line        INTEGER,
  problem     TEXT NOT NULL,
  suggestion  TEXT,                          -- prose fix
  patch       TEXT,                          -- optional raw replacement, posted as a GitHub suggestion block
  ts          TEXT NOT NULL
);

-- Migration for DBs created before `patch` existed.
ALTER TABLE comments ADD COLUMN patch TEXT;

-- Full prose report from a worker's own hand — free-form journal written
-- by the role during its work, slurped by the manager after the subagent
-- returns and inserted here verbatim. This is the retrospective tail:
-- what the role thought it was doing, why, and what it noticed along the way.
-- Manager still owns the INSERT (rule 17); the row is a projection of the
-- role's on-disk journal file, which is the source of truth.
CREATE TABLE IF NOT EXISTS worker_reports (
  report_id   INTEGER PRIMARY KEY AUTOINCREMENT,
  slot_id     TEXT NOT NULL REFERENCES slots(slot_id),
  ticket_ref  TEXT NOT NULL,
  role        TEXT NOT NULL,                 -- 'coder'|'tester'|'docs'|'reviewer'
  round       INTEGER NOT NULL,
  return_text TEXT,                          -- the subagent's final text
  journal     TEXT,                          -- contents of the journal file, or null if absent
  journal_path TEXT,                         -- path relative to project root
  ts          TEXT NOT NULL
);

-- Every mutating command suppressed in dry-run mode.
CREATE TABLE IF NOT EXISTS gated_calls (
  gated_id   INTEGER PRIMARY KEY AUTOINCREMENT,
  slot_id    TEXT NOT NULL REFERENCES slots(slot_id),
  ticket_ref TEXT,
  command    TEXT NOT NULL,
  ts         TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_slot   ON events(slot_id);
CREATE INDEX IF NOT EXISTS idx_events_ticket ON events(ticket_ref);
CREATE INDEX IF NOT EXISTS idx_events_ts     ON events(ts);
CREATE INDEX IF NOT EXISTS idx_slots_ticket  ON slots(ticket_ref);
CREATE INDEX IF NOT EXISTS idx_slots_started ON slots(started_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_slots_seq ON slots(seq);
CREATE INDEX IF NOT EXISTS idx_costs_slot    ON costs(slot_id);
CREATE INDEX IF NOT EXISTS idx_artifacts_slot ON artifacts(slot_id);
CREATE INDEX IF NOT EXISTS idx_worker_reports_slot ON worker_reports(slot_id);
CREATE INDEX IF NOT EXISTS idx_worker_reports_ticket ON worker_reports(ticket_ref);
CREATE INDEX IF NOT EXISTS idx_comments_ticket ON comments(ticket_ref);
CREATE INDEX IF NOT EXISTS idx_comments_slot ON comments(slot_id);
