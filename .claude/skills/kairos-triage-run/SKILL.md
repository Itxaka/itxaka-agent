---
name: kairos-triage-run
description: Run one slot of the Kairos triage agent. Spawns two kairos-triage-manager subagents, one per seat with rotating modes, to progress tickets (or chain across several non-committing iterations per rule 11a, or idle if the queue is empty). Invoke manually with `/kairos-triage-run`, or wire to a `/schedule` routine that ticks every 15 minutes on active weekdays inside the working window.
---

# kairos-triage-run

This skill runs exactly **one slot** of the Kairos triage agent.

A slot is 15 minutes by default (`schedule.slot_minutes` in `config/config.yaml`). The scheduler is expected to invoke this skill once per slot. Manual invocation is also supported for smoke tests and dry runs. Within a slot the manager may chain non-committing iterations (rule 11a) — up to five candidate tickets touched by one invocation — so a "slot" is a scheduling unit, not necessarily a single ticket.

## What this skill does

1. Confirm the current working directory is a `kairos-triage-agent` project (contains `RULES.md`, `config/config.yaml`, `.claude/agents/kairos-triage-manager.md`). If not, refuse and tell the user to `cd` into the project.
2. Back up local state first: `tar czf workspace/.state-backups/state-$(date -u +%Y%m%dT%H%M%SZ).tgz -C workspace .state` (create the directory if needed) and keep only the newest 20 archives. Envelopes are untracked, so this is the only way back after a bad delete.

3. Read the seats file `workspace/.state/seats.json` (see "Seats and rotation" below). Spawn one `kairos-triage-manager` per seat in a single `Agent` block, so they run side by side:

   ```
   Run one slot of the Kairos triage agent. Follow your agent-file
   instructions exactly. Working directory: <absolute path>.
   Mode: <seat mode>
   ```

   If neither seat is in `review` mode, add the line `Also: 8e` to the prompt of seat A, so re-review requests and PRs waiting on their authors still get checked. Each mode's order is in "Slot mode" in the manager file.

4. Wait for both managers. Report both summary lines back to the user without paraphrasing them; the summaries are the record of what happened this slot. Then update the seats file from each manager's `slot-result:` line.

## Seats and rotation

No seat keeps one role for long. `workspace/.state/seats.json` holds the two seats:

```json
{"A": {"mode": "build",  "slots_in_mode": 0, "idle_streak": 0},
 "B": {"mode": "review", "slots_in_mode": 0, "idle_streak": 0}}
```

If the file is missing, create it with the values above. After each slot, for each seat:

- Add 1 to `slots_in_mode`.
- `slot-result: idle` adds 1 to `idle_streak`; `slot-result: work`, or a missing line, resets it to 0.
- Rotate the seat when `idle_streak` reaches 4 (nothing to do for 4 slots in a row) or `slots_in_mode` reaches 8 (the role has been held long enough). The new mode is the next one in the cycle `review` → `qa` → `build` → `review`. Reset both counters.

Both seats may hold the same mode; the manager file keeps two managers off the same ticket. A seat rotated away from `review` comes back to it within a few cycles, and `Also: 8e` covers the gap meanwhile.

The hunt (rule 23) runs beside the seats on its own 30-minute cadence; see the `kairos-triage-hunt` skill.

## What this skill does NOT do

- It does not loop. One invocation = one slot. The scheduler handles cadence.
- It does not interpret the manager's actions or second-guess its decisions. That is what the ground rules and the manager's system prompt are for.
- It does not talk to GitHub itself. The manager (and only the manager) does that.

## Wiring the scheduler

To run this on a cadence, create a scheduled routine via the `schedule` skill:

```
/schedule create every 15 minutes 8:00-17:00 mon-fri run /kairos-triage-run
```

Adjust the times to match `schedule.working_hours` in `config/config.yaml`. Adjust the days to match `schedule.active_weekdays`.

## Dry runs

To exercise the pipeline without any GitHub side-effects, either set `KAIROS_TRIAGE_DRY_RUN=1` in the environment before invoking, or `touch workspace/.dry-run` inside the project (the flag file is what a `/loop` cadence uses to toggle between dry-run and live without editing the loop prompt; `rm workspace/.dry-run` flips it back). The manager reads this at startup: it still fetches GitHub state, still runs the rule engine, still spawns worker subagents, and still updates the local envelope, but it does not `gh` any writes and does not `git push`. The composed audit trail is printed to stdout inside `--- BEGIN AUDIT (dry-run) ---` fences and appended to `workspace/.logs/dry-run-<ts>.log`. See the manager's "Dry-run mode" section for the exact set of gated calls.

In dry-run mode the working-window check is downgraded to a warning so smoke tests can run at any hour.

## Pinning a ticket for a smoke test

Set `KAIROS_TRIAGE_PICK=<owner>/<repo>#<n>` alongside the dry-run flag to force the manager to work that exact ticket instead of walking the queue. Other rules still apply — the pinned ticket must not be assigned to a human and must not be skipped by `config/rules.yaml`.
