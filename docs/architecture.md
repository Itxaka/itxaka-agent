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

    # Compute the release-meta priority queue for this cycle (rule 16).
    meta = pick_next_release_meta(kairos-io/kairos)
    priority_refs = extract_references(meta) if meta else set()

    # Priority 1 — PR reviews.
    for source in [priority_refs, "all"]:
        for repo in repositories where watch.pull_requests:
            pr = next open PR missing a review from us, restricted to `source`
            if pr:
                enqueue pr for reviewer
                break

    # Priority 2 — issue triage (only if no PR needed a review).
    if reviewer queue empty:
        for source in [priority_refs, "all"]:
            for repo in repositories where watch.issues:
                issue = next open unassigned issue matching rules, restricted to `source`
                if issue and taken_this_cycle < max_new_tickets_per_cycle:
                    enqueue issue for investigator
                    break

    reviewer.run_one()      # PR review, may span multiple slots
    investigator.run_one()  # issue investigation, may span multiple slots
```

Two workers, not one: the reviewer consumes PRs, the investigator consumes issues. Both are slow (clone, build, boot VMs) and both are gated by the slot scheduler (rule 11, 15-minute cadence). A slot only commits to a ticket when it did real work; a non-committing iteration (dormant per rule 12b, quiet own PR per rule 8a, or a comment-only exchange) chains into the next pick without waiting for the next slot boundary — up to five iterations per invocation (rule 11a).

## Components

The single "investigator" and "reviewer" boxes below are actually **a collective of roles** coordinated by a manager — see [`agent-roles.md`](./agent-roles.md) and RULES.md rules 17-19. From the scheduler's point of view they are still one worker each; internally they are a coder/tester/docs/reviewer pipeline funneling through the manager.

- **scheduler** — owns the slot clock. Wakes at every slot boundary, checks the working window, and either advances current work or picks up next work. Rule 11.
- **manager** — sole GitHub-write authority; dispatches worker roles for the current ticket, drives the per-ticket state machine, escalates on unresolved review disagreements.
- **poller** — GitHub API client, lists issues/PRs, applies etag caching so idle cycles are free.
- **rule engine** — evaluates `config/rules.yaml` against a ticket, emits an action.
- **release tracker** — scans open issues for release-meta tickets, sorts them by semver, drops any whose tag already exists, and returns the priority reference set (rule 16).
- **workspace manager** — owns `workspace/`, guarantees rule 6 (paths never escape it) and rule 7 (default branch is fresh before branching).
- **reviewer** — per-PR state machine: read diff → read linked issues/commits → pull branch → (optionally) build ISO and boot in QEMU → post review. Rules 8 and 9.
- **investigator** — per-issue state machine: assign → label `in-progress` → announce → reproduce → report → (optionally) PR. Rules 4, 10, 12.
- **reporter** — wraps GitHub issue comments, PR creation, label edits. Enforces rule 4 (never silent) and rule 1 (PRs from fork only).
- **repro driver** — thin wrapper over `auroraboot` + QEMU, backed by the `driving-qemu-vms` skill's conventions. ISO build cache is unbounded (rule 9).

## State

Per-ticket state (phase, round, artifact paths, reviewer history, pre-review context) lives in a JSON envelope at `workspace/.state/<owner>_<repo>/<ticket>/envelope.json`. Rule 19 makes this file the source of truth for state-machine progression — the manager reads it at the start of every slot and writes it at every transition. Workers write to it; the reviewer does not (it returns its verdict as text and the manager appends it).

An additional SQLite ledger at `workspace/.state/audit.sqlite` mirrors every slot, event, verdict, artifact, cost tick, and gated call — see `config/audit-schema.sql`. This is a dashboard feed, not a coordination channel; only the manager writes to it, workers do not (rule 17). Both live and dry-run runs write, since the DB is local-only. The manager runs `bash dashboard/generate.sh` as the last step of every slot so `dashboard/index.html` stays in step with the ledger.

## Resolved decisions

The earlier draft's open questions are all answered by the current implementation:

- **Runtime.** Claude Code-native. No standalone binary — the manager is a subagent (`.claude/agents/kairos-triage-manager.md`), workers are subagents dispatched via the `Agent` tool, and the scheduler is a `/schedule` routine that invokes the `/kairos-triage-run` skill once per slot. See `docs/claude-code-integration.md`.
- **Dry-run gating.** `KAIROS_TRIAGE_DRY_RUN=1` at startup gates every mutating `gh` call and every `git push`; reads and envelope writes still happen so the pipeline exercises end to end. `KAIROS_TRIAGE_PICK=<owner>/<repo>#<n>` pins a target for smoke tests. See the "Dry-run mode" section of the manager agent file.
- **Isolation.** Every role runs in its own subprocess (fresh subagent = fresh LLM context). Rule 22. Concurrency is 1 while the Second Foundation stabilises.
