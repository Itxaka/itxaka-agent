# dashboard

Static HTML viewer for the audit ledger at `workspace/.state/audit.sqlite`. No server, no JS deps.

## Generate

```
./dashboard/generate.sh
```

Or point at a different DB / output path:

```
./dashboard/generate.sh path/to/audit.sqlite dashboard/out.html
```

Then open `dashboard/index.html` in a browser:

```
xdg-open dashboard/index.html   # linux
open dashboard/index.html       # macOS
```

The output is regenerable and gitignored — commit the DB, not the HTML. Actually the DB is also gitignored (`workspace/*`), so nothing generated ships in the repo. If you want to share a snapshot, generate the HTML on a machine with the DB and pass the file around.

## What's in it

- **Overview** — slot count, ticket count, verdict tallies, total tokens, total USD, gated-call count.
- **Recent slots** — one row per manager invocation, styled by outcome.
- **Tickets touched** — dimension table, author + third-party flag + last observed phase.
- **Reviewer verdicts** — one row per round.
- **Cost per slot** — tokens and USD per role invocation.
- **Artifacts produced** — every commit, test, doc, log, screendump, PR review, or issue comment recorded during a slot (dry-run counts).
- **Slot detail** (collapsible) — per-slot events timeline, worker journals (full prose from each role), and gated calls.

## Dependencies

`bash`, `sqlite3` (>= 3.43 for `readfile`), `sed`, `python3` (only for HTML-escaping journal text).
