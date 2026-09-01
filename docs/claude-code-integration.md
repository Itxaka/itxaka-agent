# Claude Code integration

The triage agent runs entirely inside Claude Code. It is not a standalone binary; it is a manager agent that dispatches worker subagents through the Agent tool. Every rule in `RULES.md` maps onto a Claude Code primitive.

## Mapping

| Rule concept                                | Claude Code primitive                                                             |
|---------------------------------------------|-----------------------------------------------------------------------------------|
| Manager                                     | `.claude/agents/kairos-triage-manager.md`                                         |
| Coder / tester / docs / reviewer            | `.claude/agents/kairos-triage-<role>.md`                                          |
| Rule 22 subprocess isolation                | Every `Agent` invocation is already a fresh subagent with a clean context         |
| Rule 22 model per role                      | `model:` frontmatter on each agent file (`sonnet`, `opus`, `haiku`, `fable`)      |
| Rule 17 manager-only writes                 | Manager alone owns `Bash` (for `gh`, `git push`); workers get read/edit tools only |
| Rule 19 envelope                            | JSON file on disk under `workspace/.state/<repo>/<ticket>/envelope.json`          |
| Rule 20 audit publish                       | Manager runs `gh issue comment` / `gh pr create` after the reviewer approves      |
| Rule 21 cost budget                         | Manager totals `subagent_tokens` from each Agent result into `workspace/.state/budget.json` |
| Rule 11 30-minute slot loop, 08:00–17:00    | `/schedule` cloud routine — one manager invocation per slot                        |
| GitHub reads                                | `gh api` / `gh issue list` via `Bash`                                             |
| QEMU reproduction (rules 3, 9)              | Tester invokes the `driving-qemu-vms` and `testing-immucore-with-qemu` skills     |

## Entry points

- **Scheduled** — a `/schedule` cloud routine ticks every 30 minutes on active weekdays inside the working window and invokes `/kairos-triage-run`, which spawns the manager for one slot's work.
- **Manual** — running `/kairos-triage-run` from an interactive session does the same thing without waiting for the next tick. Useful for smoke tests and dry runs.

## One invocation, one slot

Each manager invocation is intended to progress exactly the amount of work that fits in one 30-minute slot. Concretely:

1. Load `config/config.yaml` and check the working window + budget ledger.
2. If a ticket already has an in-flight envelope, advance it by as many phases as fit in the timeout (coding → testing → docs → reviewing → manager-final).
3. If no in-flight envelope exists, pick one new ticket from the priority queue (rule 16) or the plain queue and create its envelope in `intake`.
4. On `manager-final` or `escalated`, publish the audit trail (rule 20) and close the envelope.
5. Exit. The next tick picks up where this one left off, either the same in-flight ticket in a later phase or a new ticket.

This satisfies rule 11 by construction: a new ticket is only picked at the start of a slot, and even a fast finish does not immediately grab another one — the next tick does.

## File layout added for the integration

```
.claude/
├── agents/
│   ├── kairos-triage-manager.md      # sonnet, all tools + Agent
│   ├── kairos-triage-coder.md        # opus, code edits + local git commits
│   ├── kairos-triage-tester.md       # sonnet, tests + auroraboot + QEMU
│   ├── kairos-triage-docs.md         # haiku, doc/changelog edits
│   └── kairos-triage-reviewer.md     # opus, read-only verdict
└── skills/
    └── kairos-triage-run/
        └── SKILL.md                  # spawns the manager for one slot
```
