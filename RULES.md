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
