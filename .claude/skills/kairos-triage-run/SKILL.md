---
name: kairos-triage-run
description: Run one slot of the Kairos triage agent. Spawns the kairos-triage-manager subagent to progress one ticket (or idle if there is nothing to do). Invoke manually with `/kairos-triage-run`, or wire to a `/schedule` routine that ticks every 30 minutes on active weekdays inside the working window.
---

# kairos-triage-run

This skill runs exactly **one slot** of the Kairos triage agent.

A slot is 30 minutes by default (`schedule.slot_minutes` in `config/config.yaml`). The scheduler is expected to invoke this skill once per slot. Manual invocation is also supported for smoke tests and dry runs.

## What this skill does

1. Confirm the current working directory is a `kairos-triage-agent` project (contains `RULES.md`, `config/config.yaml`, `.claude/agents/kairos-triage-manager.md`). If not, refuse and tell the user to `cd` into the project.
2. Spawn the `kairos-triage-manager` subagent with this prompt:

   ```
   Run one slot of the Kairos triage agent. Follow your agent-file
   instructions exactly. Working directory: <absolute path>.
   ```

3. Report the manager's final summary line back to the user. Do not paraphrase it — the summary is the record of what happened this slot.

## What this skill does NOT do

- It does not loop. One invocation = one slot. The scheduler handles cadence.
- It does not interpret the manager's actions or second-guess its decisions. That is what the ground rules and the manager's system prompt are for.
- It does not talk to GitHub itself. The manager (and only the manager) does that.

## Wiring the scheduler

To run this on a cadence, create a scheduled routine via the `schedule` skill:

```
/schedule create every 30 minutes 8:00-17:00 mon-fri run /kairos-triage-run
```

Adjust the times to match `schedule.working_hours` in `config/config.yaml`. Adjust the days to match `schedule.active_weekdays`.

## Dry runs

To exercise the pipeline without any GitHub side-effects, either set `KAIROS_TRIAGE_DRY_RUN=1` in the environment before invoking, or `touch workspace/.dry-run` inside the project (the flag file is what a `/loop` cadence uses to toggle between dry-run and live without editing the loop prompt; `rm workspace/.dry-run` flips it back). The manager reads this at startup: it still fetches GitHub state, still runs the rule engine, still spawns worker subagents, and still updates the local envelope, but it does not `gh` any writes and does not `git push`. The composed audit trail is printed to stdout inside `--- BEGIN AUDIT (dry-run) ---` fences and appended to `workspace/.logs/dry-run-<ts>.log`. See the manager's "Dry-run mode" section for the exact set of gated calls.

In dry-run mode the working-window and hard-budget checks are downgraded to warnings so smoke tests can run at any hour.

## Pinning a ticket for a smoke test

Set `KAIROS_TRIAGE_PICK=<owner>/<repo>#<n>` alongside the dry-run flag to force the manager to work that exact ticket instead of walking the queue. Other rules still apply — the pinned ticket must not be assigned to a human and must not be skipped by `config/rules.yaml`.
