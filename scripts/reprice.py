#!/usr/bin/env python3
"""Recompute the usd field of every budget ledger entry from its token count,
using config/model-pricing.yaml and the `model:` of each role's agent file.

Run after appending a ledger entry, after editing the pricing YAML, or to fix
entries written before the pricing table existed.

Usage:  python3 scripts/reprice.py [ledger_path]
Default ledger: workspace/.state/budget.json
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent
PRICING = ROOT / "config" / "model-pricing.yaml"
AGENTS = ROOT / ".claude" / "agents"
LEDGER = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "workspace/.state/budget.json"


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

    if not LEDGER.exists():
        print(f"no ledger at {LEDGER}, nothing to reprice")
        return

    try:
        ledger = json.loads(LEDGER.read_text())
    except json.JSONDecodeError:
        sys.exit(f"ledger at {LEDGER} is not valid JSON, not touching it")
    if not isinstance(ledger, list):
        sys.exit(f"ledger at {LEDGER} is not a JSON array, not touching it")

    n = 0
    for entry in ledger:
        if "tokens" not in entry:
            continue
        role = entry.get("role")
        if role not in rate:
            print(f"  warning: unknown role={role!r} at ts={entry.get('ts')}, usd left as is")
            continue
        entry["usd"] = entry["tokens"] * rate[role]
        n += 1
    LEDGER.write_text(json.dumps(ledger, indent=2))
    print(f"repriced {n} of {len(ledger)} ledger entries in {LEDGER}")

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"done at {ts}")


if __name__ == "__main__":
    main()
