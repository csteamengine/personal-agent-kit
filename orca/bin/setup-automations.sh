#!/bin/bash
# setup-automations.sh: recreate the kit's Orca automations on a fresh install,
# through the `orca automations` CLI. Idempotent by name: an automation that
# already exists is left alone (edit it in the app or with `orca automations edit`).
#
# Usage: setup-automations.sh --repo <selector> [--provider claude] [--dry-run]
#   --repo      the Orca repo the automations run against (`orca repo list`)
#   --provider  agent for the automations that do run one (default: claude)
#
# Two automations:
#   card-note sweep   every 5 minutes. Script-only: the precheck does the work and
#                     always exits 1, so Orca records a skipped run and no agent
#                     turn is ever spent. Use this pattern for any pure-shell chore.
#   worktree reaper   weekdays 09:00. The precheck exits 0 only when a merged or
#                     closed PR's worktree holds no unsaved work; the agent then
#                     lists the candidates for you and removes nothing.
# Stock Orca commands used: automations list, automations create.
set -uo pipefail
ORCA="${ORCA_BIN:-orca}"
HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="${ORCA_KIT_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-kit/orca}"
repo=""; provider="claude"; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --provider) provider="${2:-}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] || { sed -n '6,8p' "$0" >&2; exit 2; }

existing="$("$ORCA" automations list --json 2>/dev/null | jq -r '.result.automations[]?.name')" \
  || { echo "orca automations list failed; is Orca running and the CLI installed?" >&2; exit 1; }

create() {  # name trigger precheck prompt
  if printf '%s\n' "$existing" | grep -qxF "$1"; then echo "EXISTS   $1"; return 0; fi
  if [ "$dry" -eq 1 ]; then
    printf 'DRY      orca automations create --name %q --trigger %q --precheck %q --prompt %q --provider %q --repo %q\n' \
      "$1" "$2" "$3" "$4" "$provider" "$repo"
    return 0
  fi
  "$ORCA" automations create --name "$1" --trigger "$2" --precheck "$3" --prompt "$4" \
    --provider "$provider" --repo "$repo" --json >/dev/null 2>&1 \
    && echo "CREATED  $1" || { echo "FAILED   $1" >&2; return 1; }
}

rc=0
create "Card note sweep" "*/5 * * * *" \
  "$HERE/orca-card-note.sh sweep >/dev/null 2>&1; exit 1" \
  "This automation is script-only and should never reach an agent. If you are reading this, stop and do nothing." || rc=1
create "Worktree reaper" "0 9 * * 1-5" \
  "$HERE/worktree-reaper.sh >/dev/null 2>&1" \
  "Read $STATE/reaper-candidates.txt. Each line is a worktree whose PR is merged or closed and which has no unsaved work. List them in one table (path, branch, PR number). Remove nothing: removal is the user's call, through 'orca worktree rm'. Then set this workspace's status to In review." || rc=1
exit $rc
