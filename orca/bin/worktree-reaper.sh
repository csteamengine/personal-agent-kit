#!/bin/bash
# worktree-reaper.sh: report git worktrees whose PR is merged or closed and which
# hold no unsaved work. Read-only: prints a plan, deletes nothing.
# Exit 0 if there is something to reap, 1 if not, so it works as an Orca
# automation precheck (exit 0 runs the automation's agent, anything else skips).
#
# Usage: worktree-reaper.sh [<main checkout> ...]
#   With no arguments, reads one path per line from $ORCA_KIT_CONFIG/reaper-repos.
#   Candidates (one worktree path per line) are written to
#   $ORCA_KIT_STATE/reaper-candidates.txt, replaced on every run.
#
# Unsaved work disqualifies a worktree, no exceptions: uncommitted changes, or
# commits that are on no remote branch. Stashes are deliberately NOT checked: refs/stash
# lives in the common git dir and is shared by every worktree of the repo, so
# removing a worktree never destroys one, and checking it blocks every worktree.
# PR lookup: `gh pr list --head <branch>` against the checkout's own origin.
# Never removes anything itself; remove through `orca worktree rm` so Orca's
# board stays in sync.
set -uo pipefail

CONFIG="${ORCA_KIT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-kit/orca}"
STATE="${ORCA_KIT_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-kit/orca}"
OUT="$STATE/reaper-candidates.txt"
mkdir -p "$STATE"; : > "$OUT"

REPOS=("$@")
if [ ${#REPOS[@]} -eq 0 ] && [ -f "$CONFIG/reaper-repos" ]; then
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    REPOS+=("${line/#\~/$HOME}")
  done < "$CONFIG/reaper-repos"
fi
[ ${#REPOS[@]} -gt 0 ] || { echo "no repos: pass main checkout paths or list them in $CONFIG/reaper-repos" >&2; exit 2; }

for MAIN in "${REPOS[@]}"; do
  REPO=$(basename "$MAIN")
  while read -r WT; do
    [ -d "$WT" ] || continue

    BRANCH=$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)
    { [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; } && continue

    DIRTY=$(git -C "$WT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    # Commits on no remote branch at all. Stricter than @{upstream}..HEAD, which
    # silently reads 0 once a merged PR's remote branch has been deleted.
    UNPUSHED=$(git -C "$WT" log --oneline HEAD --not --remotes 2>/dev/null | wc -l | tr -d ' ')

    PR=$(cd "$WT" && gh pr list --head "$BRANCH" --state all --json number,state --limit 1 \
           --jq '.[0] | "\(.number)\t\(.state)"' 2>/dev/null)
    NUM="${PR%%$'\t'*}"; ST="${PR#*$'\t'}"
    SIZE=$(du -sh "$WT" 2>/dev/null | cut -f1)

    if [ -z "$PR" ]; then
      echo "KEEP   $REPO $SIZE  $BRANCH  (no PR found)"
    elif [ "$ST" != "MERGED" ] && [ "$ST" != "CLOSED" ]; then
      echo "KEEP   $REPO $SIZE  #$NUM $ST  $BRANCH"
    elif [ "$DIRTY" != "0" ] || [ "$UNPUSHED" != "0" ]; then
      echo "KEEP   $REPO $SIZE  #$NUM $ST  $BRANCH  (UNSAVED: $DIRTY dirty, $UNPUSHED unpushed)"
    else
      echo "REAP   $REPO $SIZE  #$NUM $ST  $BRANCH"
      echo "$WT" >> "$OUT"
    fi
  done < <(git -C "$MAIN" worktree list --porcelain | awk '/^worktree /{ if (n++) print substr($0, 10) }')   # first entry is the main checkout
done

[ -s "$OUT" ] && exit 0 || exit 1
