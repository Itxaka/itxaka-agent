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

| Path              | Purpose                                                        |
|-------------------|----------------------------------------------------------------|
| `config/`         | Runtime configuration (repos to watch, cadence, takeover rules)|
| `docs/`           | Design notes and operational documentation                     |
| `workspace/`      | Scratch directory where the agent clones repos (gitignored)    |
| `RULES.md`        | The ground rules the agent must obey                           |

## Status

Bootstrapping. No agent code yet — this commit sets up directory layout, rules, and configuration skeletons only.
