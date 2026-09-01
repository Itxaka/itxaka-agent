# Agent roles

The triage agent is not a single loop. It is a small fleet of specialized roles coordinated by a **manager**. Workers produce artifacts, review each other's output, and pass drafts back and forth until they agree the ticket is done. Only the manager touches GitHub. See `RULES.md` rules 17, 18, 19 for the hard constraints this document elaborates on.

## Roles

### Manager

Sole owner of every GitHub state change and every `git push`. Runs the per-ticket state machine (below), dispatches work, collects results, applies rules 4 / 5 / 12 / 13 to every human-visible artifact, and performs the terminal action for a ticket (final comment, PR open, label removal, or escalation).

- **Inputs:** rule-engine action from the poll cycle, release-meta priority queue.
- **Outputs:** GitHub API calls, `git push` to the fork, state-machine transitions.
- **Never:** writes code, writes tests, writes docs, or forms opinions about a diff. Purely orchestration and communication.

### Coder

Implements the code change for an issue-driven ticket. Reads the issue, the code the issue points at, and the recent git history for that area. Produces commits on a working branch under `workspace/<repo>/`. For rule 15 bug fixes, the coder produces phase 2 (the fix) and phase 3 (the flipped assertion); phase 1 belongs to the tester.

- **Inputs:** issue payload, workspace, prior reviewer notes for this ticket.
- **Outputs:** local commits, a short summary artifact naming the touched files and the intent.
- **Never:** calls the GitHub API, pushes to any remote, opens a PR.

### Tester

Owns rule 14 and rule 15 phase 1. Writes new tests, runs the suite, and — when the change touches boot/install/upgrade/reset behavior — builds an ISO and drives the reproduction VM through the `driving-qemu-vms` conventions. Produces test-run logs and screendumps for the manager to publish.

- **Inputs:** issue payload, current workspace state, coder's draft.
- **Outputs:** new test files, run logs, screendumps, ISOs (kept in `workspace/.artifacts`), a short summary artifact.
- **Never:** edits production code, calls the GitHub API.

### Docs

Updates user-facing documentation when a change alters behavior humans read about — cloud-init keys, CLI flags, boot flow. For most bug fixes this is a no-op and the role returns "not applicable" immediately.

- **Inputs:** coder's draft, issue payload.
- **Outputs:** doc edits, changelog entry, a short summary artifact.
- **Never:** touches code that is not a documentation file, calls the GitHub API.

### Reviewer

Reads the combined artifact set produced by coder + tester + docs and issues one verdict per round: **approve** or **changes-requested** with an itemized list of comments. Same checks a human maintainer would apply — correctness, missing tests, style, scope creep, matching the target repo's conventions.

- **Inputs:** full artifact bundle from the round.
- **Outputs:** verdict plus specific comments (file, line, suggestion).
- **Never:** edits files, calls the GitHub API. The reviewer says what is wrong; the coder/tester/docs fix it.

## Handoff envelope

Every handoff carries this JSON envelope, persisted to `workspace/.state/<repo>/<ticket>/envelope.json`:

```json
{
  "ticket":  "kairos-io/kairos#1234",
  "phase":   "coding | testing | docs | reviewing | manager-final | escalated | done",
  "round":   0,
  "branch":  "triage/1234-short-slug",
  "artifacts": {
    "commits":     ["abcd123: fix: ...", "..."],
    "tests":       ["path/to/new_test.go", "..."],
    "docs":        ["docs/foo.md"],
    "logs":        ["workspace/.artifacts/logs/run-2026-09-01T09-00.log"],
    "screendumps": ["workspace/.artifacts/screens/boot-fail.ppm"]
  },
  "history": [
    { "round": 0, "verdict": "changes-requested", "comments": [ ... ] }
  ]
}
```

## State machine

```
                                                        approved
[intake] --> [coding] --> [testing] --> [docs] --> [reviewing] --> [manager-final] --> [done]
                 ^                                       |
                 |             changes-requested         |
                 +---------------------------------------+
                              (round++)

                                    round > max_review_rounds
                                          |
                                          v
                                    [escalated] --> human
```

`intake` is where the manager picks up the ticket. `manager-final` is where the manager pushes the branch to the fork, opens the PR, publishes the audit trail (rule 20 — human-readable summary comment plus the redacted envelope, either inline or as a gist), links the PR from the issue, and clears `in-progress`. `escalated` is the safety valve required by rule 18; it also publishes the audit trail so the human picking up the ticket sees everything the roles produced.

## Configuration knobs

Set in `config/config.yaml` under `roles:`:

- `max_review_rounds` — hard cap on the reviewer/worker loop.
- `state_dir` — where envelopes are persisted; default `workspace/.state`.
- Per-role runtime settings (model choice, token budget, timeout) live here as well and are filled in when the runtime is chosen.

## Decisions

The design-phase open questions from an earlier draft are now locked in:

- **Isolation.** Each role runs as its own **subprocess** (`roles.isolation: subprocess`). Clean crash boundaries, fresh LLM context per role, and structural reviewer independence. Rule 22.
- **Concurrency.** The manager keeps **one ticket in flight** at a time (`roles.concurrency: 1`). Rule 11 slot alignment stays trivial. Raising this later is a config change plus per-repo workspace locking.
- **Cost caps.** Budget is **global** over a rolling window, not per-ticket. Some tickets are expensive-but-legitimate; capping them individually would either strangle or miss. See rule 21 and `config/config.yaml` `budget:`.
- **Reviewer independence.** Subprocess isolation already gives the reviewer a fresh context, so it never sees the coder's live reasoning. Model choice is per role (`roles.runtimes.<role>.model`) so an operator can further widen the perspective gap by picking a different model family for the reviewer.

## Envelope cost accounting

Envelopes carry a `cost` block that the manager updates as each role reports back. This drives the rolling-window ledger at `workspace/.state/budget.json` for rule 21.

```json
"cost": {
  "usd_total": 1.23,
  "by_role": {
    "coder":    0.85,
    "tester":   0.20,
    "docs":     0.00,
    "reviewer": 0.15,
    "manager":  0.03
  }
}
```
