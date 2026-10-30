---
name: kairos-triage-hunt
description: Run one 30-minute hunt batch of the Kairos triage agent. Spawns one kairos-triage-manager in `Mode: hunt`, which sends hunter subagents through a rotating set of Kairos repos and areas, proves and double-checks every bug, shortcoming or missing feature they find, and files them as labelled issues on kairos-io/kairos, at most 2 per batch (extras are queued for later batches). Runs on its own cadence, independent of the `/kairos-triage-run` seats.
---

# kairos-triage-hunt

This skill runs exactly **one hunt batch** (RULES.md rule 23). A batch is `hunt.batch_minutes` (30) long. It is separate from the 15-minute seat slots of `/kairos-triage-run`: it neither waits for them nor blocks them.

## What this skill does

1. Confirm the current working directory is a `kairos-triage-agent` project (contains `RULES.md`, `config/config.yaml`, `.claude/agents/kairos-triage-manager.md`). If not, refuse and tell the user to `cd` into the project.
2. Spawn one `kairos-triage-manager` subagent:

   ```
   Run one hunt batch of the Kairos triage agent. Follow your agent-file
   instructions exactly. Working directory: <absolute path>.
   Mode: hunt
   ```

3. Report the manager's summary line back to the user without paraphrasing it, with the list of issues it filed.

## Cadence

Start a batch every `hunt.batch_minutes` inside the working window (`schedule.working_hours`, `schedule.active_weekdays`). Never run two batches at once: if the previous batch is still running when the next one is due, start the next one as soon as it returns. When this runs from the same `/loop` as `/kairos-triage-run`, track the last batch start in `workspace/.state/hunt-last.json` (`{"started_at": "<ISO time>"}`) and launch a batch on any wakeup or notification where 30 minutes have passed and no batch is running.

## Dry runs

`KAIROS_TRIAGE_DRY_RUN=1` or `workspace/.dry-run` work as for `/kairos-triage-run`: hunters still investigate and verify, and the manager prints the issues it would file instead of filing them.
