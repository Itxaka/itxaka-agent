#!/usr/bin/env python3
"""Backfill slots.seq for any row where it is NULL.

Run once against an audit DB created before the `seq` column existed. Assigns
a monotonic sequence in `started_at` order, continuing from the current
`MAX(seq)` so a partial backfill can be resumed. Safe to re-run — subsequent
invocations touch nothing.

Usage:  python3 scripts/backfill-slot-seq.py [db_path]
Default DB: workspace/.state/audit.sqlite
"""

from __future__ import annotations

import pathlib
import sqlite3
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DB = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "workspace/.state/audit.sqlite"


def main() -> None:
    if not DB.exists():
        print(f"no DB at {DB}, nothing to backfill")
        return

    con = sqlite3.connect(DB)
    cur = con.cursor()

    # Ensure the column and its unique index exist even if the schema file was
    # not re-applied first — this script is often the first thing an operator
    # runs on an older DB.
    cols = {r[1] for r in cur.execute("PRAGMA table_info(slots)")}
    if "seq" not in cols:
        cur.execute("ALTER TABLE slots ADD COLUMN seq INTEGER")
    cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_slots_seq ON slots(seq)")

    next_seq = (cur.execute("SELECT COALESCE(MAX(seq),0) FROM slots").fetchone()[0] or 0) + 1
    rows = cur.execute(
        "SELECT slot_id FROM slots WHERE seq IS NULL ORDER BY started_at, slot_id"
    ).fetchall()
    for (slot_id,) in rows:
        cur.execute("UPDATE slots SET seq=? WHERE slot_id=?", (next_seq, slot_id))
        next_seq += 1

    con.commit()
    con.close()
    print(f"backfilled {len(rows)} rows in {DB}")


if __name__ == "__main__":
    main()
