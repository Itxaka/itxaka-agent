# Architecture (draft)

This file captures the intended shape of the agent as it stands today. Nothing here is code yet.

## High-level loop

```
every poll_interval:
    for repo in config.repositories:
        tickets = github.list_open_tickets(repo)
        for ticket in tickets:
            action = rules.evaluate(ticket)
            match action:
                skip              -> next
                comment_only      -> post canned comment, add labels
                investigate       -> enqueue for investigator
                escalate_to_human -> label and next
    investigator.drain(max=config.max_new_tickets_per_cycle)
```

Two loops, not one: the poll loop is cheap and fast; the investigator loop is slow (clones, builds, boots VMs) and is throttled by `max_new_tickets_per_cycle`.

## Components

- **poller** — GitHub API client, lists issues/PRs, applies etag caching so idle cycles are free.
- **rule engine** — evaluates `config/rules.yaml` against a ticket, emits an action.
- **workspace manager** — owns `workspace/`, guarantees rule 6 (paths never escape it) and rule 7 (default branch is fresh before branching).
- **investigator** — per-ticket state machine: assign → announce → reproduce → report → (optionally) PR.
- **reporter** — wraps GitHub issue comments, PR creation, label edits. Enforces rule 4 (never silent) and rule 1 (PRs from fork only).
- **repro driver** — thin wrapper over `auroraboot` + QEMU, backed by the `driving-qemu-vms` skill's conventions.

## State

The agent keeps per-ticket state (last cycle handled, current phase, notes) in a small SQLite database under `workspace/.state/agent.db`. This is a local optimization only; the ticket comment history is the source of truth humans read.

## Open questions

- Language and runtime — Go is the natural choice given the ecosystem, but this is not yet decided.
- How to gate destructive actions (PR opens, label edits) behind a dry-run mode during early development.
- Whether to run the investigator loop in-process or as a subprocess per ticket for isolation.
