#!/usr/bin/env bash
# Injects the active .scratch tracker into context at session start and after compaction.
# Always exits 0: a failure here should degrade to silence, not noise.
set -uo pipefail

# Worktree-local: links stay in this workspace, and the tracker dies with the worktree.
top="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$top" ] || exit 0
# The agent vault forbids .scratch (its CLAUDE.md); stay silent there.
[ "$top" = "{{VAULT}}" ] && exit 0
scratch="$top/.scratch"

if [ ! -d "$scratch" ]; then
  echo "No .scratch/ in this repo ($scratch). For work spanning more than one sitting, create .scratch/<topic>/TRACKER.md before planning."
  exit 0
fi

tracker="$(find "$scratch" -maxdepth 2 -name TRACKER.md -print0 2>/dev/null \
  | xargs -0 ls -t 2>/dev/null | head -1)"

if [ -z "$tracker" ]; then
  echo "$scratch exists but holds no TRACKER.md yet."
  exit 0
fi

echo "Active scratch tracker: $tracker"
echo "Re-read it in full before acting, and again immediately before editing it. First 30 lines, capped at 2,000 bytes:"
head -30 "$tracker" | head -c 2000
[ "$(head -30 "$tracker" | wc -c)" -gt 2000 ] && echo "
[truncated at 2,000 bytes; read the tracker for the rest]"
exit 0
