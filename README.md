# kairos-triage-agent

Autonomous triage agent for the [Kairos](https://github.com/kairos-io/kairos) ecosystem. Polls open issues and pull requests on a fixed interval, decides whether to take a ticket, and acts under a strict set of ground rules.

## What it does

Between 08:00 and 17:00 local time, on every 30-minute slot boundary, the agent:

1. Looks for open pull requests on `kairos-io/kairos` and `kairos-io/auroraboot` that still need a review. For each PR it takes:
   - Reads the diff, every commit message, and the PR description.
   - Follows every linked issue and referenced PR to understand the goal.
   - Pulls the branch locally and, when the change touches runtime behavior, builds an ISO and boots it under QEMU.
   - Posts a review that states what was verified and how.
2. Only if no PR needs a review, moves to open issues on `kairos-io/kairos`:
   - Filters out anything already assigned to a human contributor.
   - Applies takeover rules (see `config/rules.yaml`) to decide whether to engage.
   - For each ticket it takes: self-assigns, applies the `in-progress` label, comments announcing the investigation, clones the affected repository into `workspace/`, investigates, and reports findings — with full reproduction steps and artifacts where possible. When a code change is warranted, opens a PR **from a fork**.

Every taken slot is at least 30 minutes long. The agent does not immediately pick up new work if a task finishes early — the next-pickup decision runs at the next slot boundary.

## Ground rules

The non-negotiable behaviors are documented in [`RULES.md`](./RULES.md). Read that file before contributing to this agent's logic.

## Layout

| Path                              | Purpose                                                        |
|-----------------------------------|----------------------------------------------------------------|
| `RULES.md`                        | The ground rules the agent must obey                           |
| `config/`                         | Runtime configuration (repos to watch, cadence, takeover rules) and the audit schema |
| `.claude/agents/`                 | Manager + coder / tester / docs / reviewer subagent prompts    |
| `.claude/skills/kairos-triage-run/` | Entry-point skill that spawns the manager for one slot       |
| `docs/`                           | Design notes and operational documentation                     |
| `docs/agent-roles.md`             | Multi-role fleet layout (manager, coder, tester, docs, reviewer) |
| `dashboard/`                      | `generate.sh` static-HTML dashboard for the audit ledger      |
| `workspace/`                      | Scratch directory where the agent clones repos, keeps envelopes, and writes the audit SQLite DB (gitignored) |

## Running

The agent is Claude Code-native — no separate binary. Two entry points:

- Manually: `/kairos-triage-run` from inside a Claude Code session opened in this directory.
- Scheduled: `/schedule create every 30 minutes 8:00-17:00 mon-fri run /kairos-triage-run` (matches the working window in `config/config.yaml`).

Dry-run smoke tests: `KAIROS_TRIAGE_DRY_RUN=1 KAIROS_TRIAGE_PICK=<owner>/<repo>#<n> /kairos-triage-run`. Every gh write and `git push` is printed to stdout and to `workspace/.logs/dry-run-<ts>.log` instead of executed.

Regenerate the dashboard from the local ledger: `./dashboard/generate.sh` — opens as `dashboard/index.html` in any browser.

## Status

Operational. Full pipeline verified end to end in dry-run against real kairos-io PRs (Renovate action-pin bumps and a human-authored CI change). Live-mode `/schedule` wiring is the next step.
