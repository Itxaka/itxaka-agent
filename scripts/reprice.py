#!/usr/bin/env python3
"""Recompute costs.usd (and worker_reports / budget ledger if needed) from
config/model-pricing.yaml.

Run after editing the pricing YAML, or to backfill rows that were inserted
before the pricing table existed.

Usage:  python3 scripts/reprice.py [db_path]
Default DB: workspace/.state/audit.sqlite
"""

from __future__ import annotations

import json
import pathlib
import re
import sqlite3
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent
PRICING = ROOT / "config" / "model-pricing.yaml"
AGENTS = ROOT / ".claude" / "agents"
DB = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "workspace/.state/audit.sqlite"
LEDGER = ROOT / "workspace/.state/budget.json"


def load_pricing() -> tuple[float, dict[str, dict[str, float]]]:
    """Tiny YAML reader — flat two-level structure only. Enough for this file."""
    text = PRICING.read_text()
    blend = 0.2
    models: dict[str, dict[str, float]] = {}
    current: str | None = None
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        m = re.match(r"^blend_ratio_output:\s*([0-9.]+)", line)
        if m:
            blend = float(m.group(1))
            continue
        if line == "models:":
            current = "__models_root__"
            continue
        m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if m and current is not None:
            current = m.group(1)
            models[current] = {}
            continue
        m = re.match(r"^    (input|output):\s*([0-9.]+)", line)
        if m and current and current != "__models_root__":
            models[current][m.group(1)] = float(m.group(2))
    return blend, models


def load_role_models() -> dict[str, str]:
    """Parse `model:` from each agent file's YAML frontmatter."""
    out: dict[str, str] = {}
    for f in AGENTS.glob("kairos-triage-*.md"):
        role = f.stem.replace("kairos-triage-", "")
        text = f.read_text()
        # frontmatter is between the first two `---` fences
        parts = text.split("---", 2)
        if len(parts) < 3:
            continue
        for line in parts[1].splitlines():
            m = re.match(r"^model:\s*(\S+)", line)
            if m:
                out[role] = m.group(1)
                break
    return out


def blended_usd_per_token(model: str, pricing: dict, blend: float) -> float | None:
    p = pricing.get(model)
    if not p or "input" not in p or "output" not in p:
        return None
    blended = p["input"] * (1 - blend) + p["output"] * blend
    return blended / 1_000_000


def main() -> None:
    blend, pricing = load_pricing()
    roles = load_role_models()
    print(f"pricing loaded: blend={blend}, models={list(pricing)}")
    print(f"role -> model:  {roles}")

    rate: dict[str, float] = {}
    for role, model in roles.items():
        r = blended_usd_per_token(model, pricing, blend)
        if r is None:
            print(f"  warning: no pricing for role={role} model={model}")
            r = 0.0
        rate[role] = r
    print(f"role -> usd/token: { {k: f'{v:.3e}' for k,v in rate.items()} }")

    if not DB.exists():
        print(f"no DB at {DB}, nothing to reprice")
        return

    con = sqlite3.connect(DB)
    cur = con.cursor()
    cur.execute("SELECT cost_id, role, tokens FROM costs")
    rows = cur.fetchall()
    n = 0
    for cost_id, role, tokens in rows:
        usd = tokens * rate.get(role, 0.0)
        cur.execute("UPDATE costs SET usd=? WHERE cost_id=?", (usd, cost_id))
        n += 1
    con.commit()
    con.close()
    print(f"repriced {n} costs rows in {DB}")

    if LEDGER.exists():
        try:
            ledger = json.loads(LEDGER.read_text())
        except json.JSONDecodeError:
            print(f"ledger at {LEDGER} not JSON-array, skipped")
            return
        if isinstance(ledger, list):
            for entry in ledger:
                r = rate.get(entry.get("role"), 0.0)
                if "tokens" in entry:
                    entry["usd"] = entry["tokens"] * r
            LEDGER.write_text(json.dumps(ledger, indent=2))
            print(f"repriced {len(ledger)} ledger rows in {LEDGER}")

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"done at {ts}")


if __name__ == "__main__":
    main()
