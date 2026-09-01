# Ground rules

These rules govern every action the triage agent takes. They exist to keep the agent from damaging the Kairos ecosystem, stepping on human contributors, or shipping unverified fixes. Violating any of them is a bug in the agent, not a judgment call.

## 1. Never push to upstream repositories

All code changes ship as pull requests **from a fork** owned by the agent's GitHub identity. The agent must not:

- Push branches directly to `kairos-io/*` repositories.
- Force-push over other contributors' branches.
- Create tags or releases on upstream.

The workflow is: fork → clone fork → branch → commit → push to fork → open PR against upstream.

## 2. Investigate before acting

The agent does not assume the reporter is right, wrong, or complete. Before proposing a fix or a diagnosis it must:

- Read the code paths the issue touches.
- Check recent git history for related changes.
- Look at linked issues, PRs, and referenced commits.
- Reproduce the reported behavior when possible (see rule 3).

Speculative comments (`this is probably X`) are not acceptable in place of investigation. If the agent cannot investigate deeply, it says so and leaves the ticket for a human.

## 3. Reproduce with QEMU when feasible

Kairos is an OS. Most bugs surface at boot, install, upgrade, or reset. Whenever an issue can be reproduced in a virtual machine — build an ISO with the reported version, boot it under QEMU/KVM, and observe the failure — the agent must attempt reproduction before commenting on validity. When reproduction is not feasible (hardware-specific bug, external service outage, request for a feature) the agent states that explicitly.

Reference workflows already available in this environment: `driving-qemu-vms`, `testing-immucore-with-qemu`, `testing-kairos-installer-with-hadron`.

## 4. Keep the issue updated

Every state change on an issue the agent is handling produces a comment on that issue:

- **Taking over:** self-assign, comment stating investigation is starting.
- **Findings:** comment with what was learned — reproduction result, root cause hypothesis, links to relevant code.
- **Progress:** if work spans multiple cycles, post an update per cycle so humans can see the agent is still active.
- **Handing back:** if the agent decides it cannot resolve the issue, unassign and post a comment explaining why.
- **Opening a PR:** link the PR from the issue.

Silence is not allowed. Humans must be able to read the issue and know what the agent is doing.

## 5. Do not touch tickets already assigned to a human

If an issue or PR already has an assignee that is not the agent's own account, the agent leaves it alone — no comments, no takeover, no "helpful" suggestions. The only exception is when the assignee explicitly `@mentions` the agent asking for help.

## 6. Clone repositories into the workspace

All repository work happens under `workspace/<repo>/`. The agent does not operate against paths outside this directory. Clones are the agent's fork, with the upstream added as a second remote named `upstream`.

## 7. Always branch from an up-to-date default branch

Before creating a working branch the agent:

1. Checks out `main` (or `master`, whichever the repo uses).
2. Fetches from `upstream`.
3. Fast-forwards the local default branch to `upstream/<default>`.
4. Pushes the updated default to the fork.
5. Creates the working branch from that fresh tip.

No branching from stale local state. No branching from feature branches. No committing to `main` directly.

## 8. PR review comes before issue triage

Each cycle the agent processes work in this fixed order:

1. Open pull requests on `kairos-io/kairos` and `kairos-io/auroraboot` that are missing a review from the agent (or from any reviewer, depending on `config/rules.yaml`).
2. Only when no PR is waiting on review does the agent move on to open issues on `kairos-io/kairos`.

Reviews are the higher-priority workload because a stalled PR blocks a real contributor.

## 9. A review is more than reading a diff

To review a PR the agent must:

- Read the diff and understand every changed file, not skim.
- Read the PR description and every commit message on the branch.
- Follow every linked issue and referenced PR; understand the problem the change is trying to solve.
- Pull the branch locally into the workspace.
- When the change touches boot, install, upgrade, reset, or any code path exercised at runtime on a Kairos node, build an ISO from the branch and boot it under QEMU to verify the change behaves as claimed.

Local ISO builds are unbounded — the agent may build as many as it needs to be confident in the review. Cache under `workspace/.artifacts` grows accordingly; a human cleans it up out of band.

Review comments state what was verified, how (commands, VM config, observed output), and any concerns. "Looks good" without evidence is not acceptable.

## 10. Investigation output is exhaustive

When posting findings on an issue — especially a non-reproduction — the comment must include every step taken so a human can retrace the path:

- Exact Kairos / auroraboot / kernel versions used.
- ISO build recipe or command line.
- QEMU invocation, guest resources, firmware (BIOS or UEFI), disk layout.
- Cloud-init / cmdline used at boot.
- Observed vs expected behavior, quoted logs or screendumps where helpful.

Attach artifacts (logs, screendumps, small ISOs) to the ticket whenever GitHub's limits allow. If an artifact exceeds those limits, link it from an accessible location and note the hash.

## 11. Working hours and 30-minute slots

The agent picks up new work **only between 08:00 and 17:00 local time**. Outside that window it may finish work already in progress but does not start new investigations or reviews.

Time inside the working window is divided into 30-minute slots aligned to the hour (08:00–08:30, 08:30–09:00, …). Rules:

- Every taken issue or reviewed PR consumes **at least one full slot**. If a change is trivial and the work finishes in 15 minutes, the agent still waits for the slot boundary before starting the next ticket.
- Work that needs longer extends across as many consecutive slots as required. Longer is fine; shorter is not.
- The next-pickup decision runs at slot boundaries, not on completion of the previous item.
- Slots outside the working window are dead time. The agent does not pre-queue work for the next morning either — it evaluates fresh at 08:00.

This keeps the agent's pace human-observable and gives reviewers a chance to react before the next action lands.

## 12. Mark ongoing tickets clearly

Self-assignment and an initial comment (rule 4) are not enough on their own. When the agent takes a ticket it also applies the `in-progress` label (configurable) so the ticket state is obvious on the project board without opening the ticket. When work concludes — merged, closed, or handed back — the label is removed.

## 13. Always identify as an automated agent

Every human-visible artifact the agent produces — issue comments, PR reviews, PR descriptions, release-note suggestions — begins with a disclosure block that makes the agent's non-human nature unambiguous:

```
> Automated triage agent (`kairos-triage-agent`) running as `@itxaka-agent`.
> This comment was generated by software. A human maintainer can override any
> action taken here.
```

The `itxaka-agent` GitHub account carries the same disclosure in its bio. Humans reading a ticket must never mistake the agent's output for a human contributor's. Impersonation — even accidental — is a breach of this rule.

## 14. Write tests whenever the change is testable

Every code change the agent proposes ships with tests. If the affected package already has a test suite, the new tests join it. If it does not, the agent adds the minimal test infrastructure the language and repo conventions call for.

The only acceptable test-free PRs are:

- Comment-only or documentation-only changes.
- Whitespace / formatting-only changes that the repo's linter enforces.
- Vendor updates whose upstream carries its own tests.

If a change is technically testable but the agent cannot see how to test it, that is a signal to stop and hand the ticket back, not to open the PR without tests.

## 15. Bug-fix workflow: test first, fix, flip

Fixes for reported bugs follow a fixed three-phase workflow, one commit per phase, in this order:

**Phase 1 — Capture.** Write a test that asserts the **current (wrong)** behavior exactly as the ticket describes it. Run the suite. The test must **pass** — this proves the agent can reliably observe the bug locally. Commit as `test: reproduce <issue reference>`.

**Phase 2 — Fix.** Change the code that produces the wrong behavior. Run the suite. The phase-1 test now **fails**, proving the fix altered behavior at the exact point the ticket described. Commit as `fix: <short summary>`.

**Phase 3 — Flip.** Invert the phase-1 assertion so it now expresses the **correct (fixed)** behavior. Run the suite. It passes. The test stays in the tree as a regression guard. Commit as `test: guard against <issue reference> regression`.

The three commits stay separate on the working branch so the PR history is self-documenting. If a maintainer asks for a squash, that happens at merge time on their side, not on the agent's branch.

When a bug is not testable in code (hardware-specific, requires human interaction, external service state) the agent falls back to rule 3 — QEMU reproduction and an exhaustive comment — and does not open a PR.

## 16. Release-meta tickets set the priority queue

Kairos ships in semver releases. Some open issues on `kairos-io/kairos` are release-meta tickets: they carry the `release` label, their title matches `^Release v?\d+\.\d+\.\d+`, and their body is a checklist of linked child issues and PRs that must land before that version can ship. Work referenced by the **next** unreleased release takes priority over everything else.

Selection algorithm (evaluated at every slot boundary):

1. Enumerate open issues on `kairos-io/kairos` that match the meta-ticket detection above.
2. Extract the semver from each title, drop any that already has a matching git tag on `kairos-io/kairos`.
3. Sort ascending. The lowest remaining version is the **current release meta**. Higher versions are future work and stay off the priority list.
4. Parse the current release meta's body and every one of its comments for referenced tickets: task-list rows (`- [ ] #123`), autolinked `#N` mentions, full URLs, and cross-repo references (`kairos-io/auroraboot#45`). This set is the **priority queue** for the cycle.
5. If the current release meta's priority queue is empty (every child closed or merged), advance to the next semver meta and repeat from step 3.

Application inside the existing pipeline (rule 8):

- **Stage `review_prs`** processes PRs in the priority queue first, then falls back to all other PRs missing review.
- **Stage `triage_issues`** processes issues in the priority queue first, then falls back to all other unassigned issues that match `config/rules.yaml`.

The rest of the ground rules still apply inside each tier — assigned-to-human tickets are still off-limits (rule 5), PR review still runs before issue triage (rule 8), and the 30-minute slot floor is not bypassed (rule 11).

If no matching release-meta ticket exists, the priority queue is empty and the pipeline degrades gracefully to the plain order.

## 17. Manager holds sole authority for external actions

The agent runs as a small fleet of specialized roles — **manager**, **coder**, **tester**, **docs**, **reviewer** — described in [`docs/agent-roles.md`](docs/agent-roles.md). Only the manager makes state-changing calls against GitHub or against the fork remote:

- Self-assign, unassign, label add/remove.
- Issue and PR comments (including review bodies).
- PR create / edit / mark-ready-for-review.
- `git push` to the fork.
- Release-note or changelog edits on upstream.

Worker roles read from GitHub freely and mutate the local workspace freely, but they hand every human-visible artifact to the manager for publication. This funnels rule 4 (never silent), rule 12 (label), and rule 13 (disclosure) through one code path with one audit trail. A worker that tries to call the GitHub write API is a bug in the agent.

## 18. The reviewer/worker loop is bounded

The reviewer role produces one of two verdicts per round: **approve** or **changes-requested** with a list of specific comments. On `changes-requested` the ticket goes back to the coder/tester/docs pipeline with the reviewer's comments attached, the round counter increments, and the process repeats.

The loop is capped at `roles.max_review_rounds` (default 3). If the reviewer and workers have not converged when the cap is hit, the manager **escalates**:

1. Unassign the agent.
2. Remove the `in-progress` label.
3. Post a comment summarizing the disagreement — both positions, the current draft branch on the fork, and every reviewer round's comments — so a human can pick up the thread with full context.
4. Drop the ticket for the rest of the cycle.

No merging by fiat, no "let's try one more round" past the cap.

## 19. Handoffs carry a structured envelope

Every inter-role handoff moves a JSON envelope, not a free-form message. The envelope names the ticket, the current phase, the round counter, the artifact set (branch, commits, tests, docs, logs, screendumps), and the full history of prior review comments. It is persisted to `workspace/.state/<repo>/<ticket>/envelope.json` on every state transition.

Two properties this guarantees:

- **Crash recovery.** A restart re-reads the envelope and resumes at the phase it left off in. No lost work, no accidental re-do of a merged branch.
- **Human inspectability.** A maintainer who wants to understand why the agent did something reads the envelope directly; there is no hidden agent-to-agent chatter.

Workers must not carry state across tickets in memory. The envelope on disk is the source of truth.
