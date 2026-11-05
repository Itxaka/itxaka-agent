#!/usr/bin/env bash
# Run a containerised test command and render its real terminal output as the
# rule 14a test-run PNG. The capture always starts with `git rev-parse HEAD`
# and `date -Iseconds`, then the exact `docker run ...` line and its output.
# Nothing is typed in by hand: the PNG shows only what the commands printed.
#
# Usage: [SHOT_EXPECT_SHA=<sha>] scripts/test-run-shot.sh <worktree> <out.png> -- docker run ... <test cmd>
# <worktree> must be a checkout of the code under test, never this repo.
#
# Writes <out.png> and the full log next to it (<out>.log). The PNG shows the
# last $SHOT_LINES lines (default 40) of the test output, without `go: downloading`
# noise, and with the worktree path shown as <worktree> and $HOME as ~. Exits with the test
# command's exit code, so a base-fails run still produces its image.
set -uo pipefail

usage() { echo "usage: $0 <worktree> <out.png> -- docker run ... <test cmd>" >&2; exit 2; }

[ $# -ge 4 ] || usage
wt=$1 out=$2
shift 2
[ "$1" = "--" ] || usage
shift
[ "$1" = "docker" ] && [ "${2:-}" = "run" ] || { echo "$0: the test command must be a 'docker run ...' (rule 14b)" >&2; exit 2; }
[ -d "$wt" ] || { echo "$0: no such worktree: $wt" >&2; exit 2; }
case "$out" in *.png) ;; *) echo "$0: output must end in .png" >&2; exit 2;; esac
self_top=$(cd "$(dirname "$0")/.." && pwd)
wt_top=$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null) || { echo "$0: $wt is not a git checkout" >&2; exit 2; }
[ "$wt_top" != "$self_top" ] || { echo "$0: $wt is the triage-agent repo itself; pass the worktree of the code under test" >&2; exit 2; }
if [ -n "${SHOT_EXPECT_SHA:-}" ]; then
  got=$(git -C "$wt" rev-parse HEAD)
  case "$got" in "$SHOT_EXPECT_SHA"*) ;; *) echo "$0: $wt is at $got, expected $SHOT_EXPECT_SHA" >&2; exit 2;; esac
fi

font=${SHOT_FONT:-Adwaita-Mono}
magick -list font | grep -x "  Font: $font" >/dev/null || { echo "$0: font '$font' not installed (see 'magick -list font')" >&2; exit 2; }

log=${out%.png}.log
wt_abs=$(cd "$wt" && pwd)
lines=${SHOT_LINES:-40}
cmdline="$*"

(
  cd "$wt" || exit 2
  echo "\$ git rev-parse HEAD"
  git rev-parse HEAD
  echo "\$ date -Iseconds"
  LC_ALL=C date -Iseconds
  echo "\$ $cmdline"
) > "$log" 2>&1 || { echo "$0: could not read HEAD in $wt" >&2; exit 2; }

head_lines=$(wc -l < "$log")

( cd "$wt" && "$@" ) >> "$log" 2>&1
rc=$?
echo "exit=$rc" >> "$log"

# Header (sha, date, command) stays; the test output is cut to its tail.
shot=$(mktemp)
trap 'rm -f "$shot"' EXIT
{
  head -n "$head_lines" "$log"
  total=$(( $(wc -l < "$log") - head_lines ))
  if [ "$total" -gt "$lines" ]; then
    echo "... ($(( total - lines )) earlier lines in $(basename "$log"))"
  fi
  tail -n +"$(( head_lines + 1 ))" "$log" | tail -n "$lines"
} | grep -v '^go: downloading ' | expand -t 8 \
  | sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' -e "s#$wt_abs#<worktree>#g" -e "s#$HOME#~#g" > "$shot"

magick -background '#111111' -fill '#dddddd' -font "$font" -pointsize 15 \
  label:@- -bordercolor '#111111' -border 16 "$out" < "$shot" \
  || { echo "$0: render failed" >&2; exit 2; }

echo "wrote $out and $log (test exit=$rc)" >&2
exit "$rc"
