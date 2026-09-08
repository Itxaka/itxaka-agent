#!/usr/bin/env bash
# audit-manual.sh — record a direct-agent dispatch (one that produced a PR,
# commit, or user-visible comment linked to a ticket) as a synthetic slot
# in the audit DB, so the dashboard's cost/tokens/artifacts totals include
# work done outside the manager's slot loop.
#
# DO NOT use this to backfill a manager slot — the manager records its own
# costs into `costs` / `artifacts` per role at slot close. Only use this for
# work dispatched directly from the main conversation (a `kairos-expert` /
# `hadron-build-master` / generic subagent that produced a PR, a review
# comment, or a commit, without going through `kairos-triage-run`).
#
# Usage:
#   scripts/audit-manual.sh <ticket_ref> <role> <tokens> <artifact_kind> <artifact_ref> [note]
#
# Examples:
#   scripts/audit-manual.sh kairos-io/kairos#4548 coder 216160 pr 4548 "verified downloads PR"
#   scripts/audit-manual.sh itxaka-agent/itxaka-agent@main manager 48910 commit 88cc7f9 "widen 8c filter"
#
# USD is estimated at $30 / 1M tokens (blended Opus 4.7 rate — rough). Adjust
# the RATE constant if you want a different assumption. Set USD=0 explicitly
# in the environment to skip the estimate.
set -euo pipefail

RATE_PER_MILLION=${RATE_PER_MILLION:-30}

if [ $# -lt 5 ]; then
  echo "usage: $0 <ticket_ref> <role> <tokens> <artifact_kind> <artifact_ref> [note]" >&2
  exit 2
fi

TICKET="$1"
ROLE="$2"
TOKENS="$3"
ARTIFACT_KIND="$4"
ARTIFACT_REF="$5"
NOTE="${6:-}"

DB="workspace/.state/audit.sqlite"
[ -f "$DB" ] || { echo "audit DB missing: $DB" >&2; exit 1; }

if [ "${USD:-}" = "" ]; then
  USD=$(python3 -c "print(round($TOKENS / 1000000.0 * $RATE_PER_MILLION, 4))")
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SUFFIX=$(head -c8 /dev/urandom | base32 | tr '[:upper:]' '[:lower:]' | tr -d '=' | head -c8)
SLOT_ID="manual-$(date -u +%Y%m%dT%H%M%SZ)-${SUFFIX}"

# Escape single quotes for SQL literal embedding.
esq() { printf %s "$1" | sed "s/'/''/g"; }
SLOT_ID_E=$(esq "$SLOT_ID")
TICKET_E=$(esq "$TICKET")
ROLE_E=$(esq "$ROLE")
KIND_E=$(esq "$ARTIFACT_KIND")
REF_E=$(esq "$ARTIFACT_REF")
NOTE_E=$(esq "$NOTE")
TS_E=$(esq "$TS")

sqlite3 "$DB" <<SQL
BEGIN IMMEDIATE;
INSERT INTO slots (slot_id, started_at, ended_at, wall_ms, dry_run,
                   ticket_ref, entry_reason, outcome, gated_calls,
                   envelope_writes, progress_note)
VALUES ('$SLOT_ID_E', '$TS_E', '$TS_E', 0, 0,
        '$TICKET_E', 'manual', 'finished', 0,
        0, '$NOTE_E');
INSERT INTO costs (slot_id, ticket_ref, role, tokens, usd, ts)
VALUES ('$SLOT_ID_E', '$TICKET_E', '$ROLE_E', $TOKENS, $USD, '$TS_E');
INSERT INTO artifacts (slot_id, ticket_ref, kind, ref, note, ts)
VALUES ('$SLOT_ID_E', '$TICKET_E', '$KIND_E', '$REF_E', '$NOTE_E', '$TS_E');
COMMIT;
SQL

echo "$SLOT_ID  $TICKET  $ROLE  ${TOKENS}tok  \$$USD  $ARTIFACT_KIND:$ARTIFACT_REF"
