# Architecture (draft)

This file captures the intended shape of the agent as it stands today. Nothing here is code yet.

## High-level loop

```
at every slot boundary (see schedule.slot_minutes):
    if not within working_hours on an active weekday:
        idle until next boundary

    if current_task still running:
        continue current_task
        next

    # Priority 1 — PR reviews.
    for repo in repositories where watch.pull_requests:
        pr = next open PR missing a review from us
        if pr:
            enqueue pr for reviewer
            break

    # Priority 2 — issue triage (only if no PR needed a review).
    if reviewer queue empty:
        for repo in repositories where watch.issues:
            issue = next open unassigned issue matching rules
            if issue and taken_this_cycle < max_new_tickets_per_cycle:
                enqueue issue for investigator
                break

    reviewer.run_one()      # PR review, may span multiple slots
    investigator.run_one()  # issue investigation, may span multiple slots
```

Two workers, not one: the reviewer consumes PRs, the investigator consumes issues. Both are slow (clone, build, boot VMs) and both are gated by the slot scheduler — even if work finishes early, the next pickup waits for the next slot boundary. This is rule 11.

## Components

- **scheduler** — owns the slot clock. Wakes at every slot boundary, checks the working window, and either advances current work or picks up next work. Rule 11.
- **poller** — GitHub API client, lists issues/PRs, applies etag caching so idle cycles are free.
- **rule engine** — evaluates `config/rules.yaml` against a ticket, emits an action.
- **workspace manager** — owns `workspace/`, guarantees rule 6 (paths never escape it) and rule 7 (default branch is fresh before branching).
- **reviewer** — per-PR state machine: read diff → read linked issues/commits → pull branch → (optionally) build ISO and boot in QEMU → post review. Rules 8 and 9.
- **investigator** — per-issue state machine: assign → label `in-progress` → announce → reproduce → report → (optionally) PR. Rules 4, 10, 12.
- **reporter** — wraps GitHub issue comments, PR creation, label edits. Enforces rule 4 (never silent) and rule 1 (PRs from fork only).
- **repro driver** — thin wrapper over `auroraboot` + QEMU, backed by the `driving-qemu-vms` skill's conventions. ISO build cache is unbounded (rule 9).

## State

The agent keeps per-ticket state (last cycle handled, current phase, notes) in a small SQLite database under `workspace/.state/agent.db`. This is a local optimization only; the ticket comment history is the source of truth humans read.

## Open questions

- Language and runtime — Go is the natural choice given the ecosystem, but this is not yet decided.
- How to gate destructive actions (PR opens, label edits) behind a dry-run mode during early development.
- Whether to run the investigator loop in-process or as a subprocess per ticket for isolation.
