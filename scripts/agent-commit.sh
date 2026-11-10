#!/usr/bin/env bash
# Create a commit as the triage agent with the mandatory trailer block.
#
#   scripts/agent-commit.sh -C <repo-or-worktree> [git commit args...]
#
# Identity and co-author come from config/config.yaml (agent.commit_*), so
# callers never type them. Any args after -C <dir> go straight to
# `git commit` (-m, -F, --amend, --no-edit, paths...). Trailers already in
# the message are not duplicated.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfg="$root/config/config.yaml"

get() { sed -n "s/^  $1: *\"\{0,1\}\([^\"]*\)\"\{0,1\} *$/\1/p" "$cfg" | head -1; }
name="$(get commit_name)"
email="$(get commit_email)"
coauthor="$(get commit_coauthor)"
[ -n "$name" ] && [ -n "$email" ] && [ -n "$coauthor" ] || {
    echo "agent-commit: agent.commit_name/commit_email/commit_coauthor missing in $cfg" >&2
    exit 1
}

[ "${1:-}" = "-C" ] && [ -n "${2:-}" ] || { echo "usage: $0 -C <dir> [git commit args...]" >&2; exit 2; }
dir="$2"; shift 2

git -C "$dir" -c user.name="$name" -c user.email="$email" \
    -c trailer.ifexists=addIfDifferent \
    commit \
    --trailer "Co-authored-by: $coauthor" \
    --trailer "Signed-off-by: $name <$email>" \
    "$@"

# Conventional Commits 1.0.0 (https://www.conventionalcommits.org/en/v1.0.0/):
# <type>[(scope)][!]: <description>, then an optional body after a blank line.
# A subject that does not match is rolled back so the caller can retry.
subject="$(git -C "$dir" log -1 --format=%s)"
second="$(git -C "$dir" log -1 --format=%B | sed -n 2p)"
re='^(feat|fix|build|chore|ci|docs|style|refactor|perf|test|revert)(\([a-z0-9._/-]+\))?!?: [^ ].*[^.]$'
if ! printf '%s' "$subject" | grep -Eq "$re" || [ -n "$second" ]; then
    git -C "$dir" reset -q --soft 'HEAD@{1}'
    echo "agent-commit: subject is not Conventional Commits 1.0.0: '$subject'" >&2
    echo "agent-commit: want '<type>[(scope)][!]: <description>' (no trailing period), blank line before the body; types: feat fix build chore ci docs style refactor perf test revert" >&2
    exit 1
fi
