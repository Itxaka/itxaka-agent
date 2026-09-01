# kairos-triage-agent

Autonomous triage agent for the [Kairos](https://github.com/kairos-io/kairos) ecosystem. Polls open issues and pull requests on a fixed interval, decides whether to take a ticket, and acts under a strict set of ground rules.

## What it does

Every poll cycle (default: 30 minutes) the agent:

1. Fetches open issues and pull requests from the configured Kairos repositories.
2. Filters out anything already assigned to a human contributor.
3. Applies takeover rules (see `config/rules.yaml`) to decide whether to engage.
4. For each ticket it takes:
   - Assigns itself.
   - Posts a comment announcing the investigation.
   - Clones the affected repository into `workspace/`.
   - Investigates the reported behavior — reading code, checking history, reproducing in QEMU when feasible.
   - Reports findings back on the ticket and, when a code change is warranted, opens a PR **from a fork**.

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
