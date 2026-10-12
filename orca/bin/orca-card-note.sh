#!/bin/bash
# orca-card-note.sh: the ONE writer of the script-owned part of an Orca workspace
# comment (the card's "Notes"). Every script and agent session that moves a card
# for a reason calls this instead of `orca worktree set --comment`, so the card
# says why it is in that column and the reason disappears when it goes stale.
#
# Ownership: the script-owned block is fenced by two HTML comments, which Orca's
# card markdown does not render. Anything outside the fence is yours and is
# preserved verbatim, below the block. To take a comment over by hand, delete the
# marker line in "Edit notes": the scripts then never touch it again.
#
#   <!-- orca-auto v1 src=<src> status=<statusId> at=<isoTime> -->
#   **<Verdict>**
#   <counts line>
#   Needs: <action line>
#   <!-- /orca-auto -->
#
# Usage:
#   set   --worktree <sel> --src <src> --verdict <V> [--counts <line>] [--needs <line>]
#         [--status-label <label>] [--dry-run]
#         Replace the block. With --status-label, the status is set in the SAME
#         `orca worktree set` call, resolved by label through orca-status.sh.
#         Without it, the block records the workspace's current status.
#   clear --worktree <sel> [--dry-run]      Remove the block, keep the human text.
#   sweep [--dry-run]                       Remove every block whose recorded status
#         no longer matches the card. Run it on a schedule (an automation precheck
#         works), so a card you drag elsewhere loses its stale verdict.
#
# Verdicts are a closed list, so the vocabulary cannot drift between scripts and
# sessions. Default list below; override with $ORCA_KIT_CONFIG/verdicts.txt (one
# per line). An unknown verdict exits 2. Put counts, logins, check names and
# statuses in a note, never free text copied from a PR, issue or customer record.
# Exit: 0 ok, 1 orca unreachable or worktree not found, 2 bad arguments.
#
# Stock Orca commands used: worktree show, worktree list, worktree set.
set -uo pipefail

ORCA="${ORCA_BIN:-orca}"
HERE="$(cd "$(dirname "$0")" && pwd)"
STATUS_SH="${ORCA_STATUS_SH:-$HERE/orca-status.sh}"
CONFIG="${ORCA_KIT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-kit/orca}"
DEFAULT_VERDICTS="Conflicts|CI failing|CI green|Re-review|Replied|Resolved|Drafts ready|Decision needed|Needs QA|QA passed|QA failed|QA incomplete|Ready to merge|Blocked|Could not check"
if [ -s "$CONFIG/verdicts.txt" ]; then
  VERDICTS="$(grep -v '^#' "$CONFIG/verdicts.txt" | awk 'NF' | paste -sd '|' -)"
else
  VERDICTS="$DEFAULT_VERDICTS"
fi
BEGIN_RE='<!-- orca-auto v1 [^\n]*?-->'
END_MARK='<!-- /orca-auto -->'

cmd="${1:-}"; shift || true
sel=""; src=""; verdict=""; counts=""; needs=""; label=""; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree) sel="$2"; shift 2 ;;
    --src) src="$2"; shift 2 ;;
    --verdict) verdict="$2"; shift 2 ;;
    --counts) counts="$2"; shift 2 ;;
    --needs) needs="$2"; shift 2 ;;
    --status-label) label="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# One line, no marker-breaking sequence, capped. Defends the fence, not the
# content rule: callers must still pass only counts and identifiers.
clean() { printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/-->/->/g' -e 's/<!--/<!-/g' | cut -c1-200; }

strip_block() {  # stdin comment -> stdout comment without the block, leading blank lines trimmed
  perl -0777 -pe "s{$BEGIN_RE.*?\Q$END_MARK\E\n*}{}s; s{\A\s+}{}"
}

write_comment() {  # sel newComment [statusId]
  if [ "$dry" -eq 1 ]; then
    echo "DRY: orca worktree set --worktree $1${3:+ --workspace-status $3} --comment <<"
    printf '%s\n' "$2" | sed 's/^/DRY:   | /'
    return 0
  fi
  if [ -n "${3:-}" ]; then
    "$ORCA" worktree set --worktree "$1" --comment "$2" --workspace-status "$3" --json >/dev/null 2>&1
  else
    "$ORCA" worktree set --worktree "$1" --comment "$2" --json >/dev/null 2>&1
  fi
}

case "$cmd" in
  set|clear)
    [ -n "$sel" ] || { echo "--worktree is required" >&2; exit 2; }
    wt="$("$ORCA" worktree show --worktree "$sel" --json 2>/dev/null | jq -c '.result.worktree // empty')"
    [ -n "$wt" ] || { echo "worktree $sel not found (or orca unreachable)" >&2; exit 1; }
    cur_status="$(printf '%s' "$wt" | jq -r '.workspaceStatus // ""')"
    human="$(printf '%s' "$wt" | jq -r '.comment // ""' | strip_block)"
    if [ "$cmd" = "clear" ]; then
      write_comment "$sel" "$human"; echo "CLEARED     $sel"; exit 0
    fi
    [ -n "$src" ] && [ -n "$verdict" ] || { echo "--src and --verdict are required" >&2; exit 2; }
    printf '%s' "$verdict" | grep -qxE "$VERDICTS" || { echo "unknown verdict '$verdict'; allowed: $VERDICTS" >&2; exit 2; }
    sid=""
    if [ -n "$label" ]; then
      sid="$("$STATUS_SH" id "$label" 2>/dev/null)"
      if [ -z "$sid" ]; then
        echo "NOTE        status '$label' unknown; falling back to In review" >&2
        sid="in-review"
      fi
    fi
    rec="${sid:-$cur_status}"
    block="<!-- orca-auto v1 src=$(clean "$src" | tr ' ' '_') status=$rec at=$(date -u +%Y-%m-%dT%H:%MZ) -->
**$verdict**"
    [ -n "$counts" ] && block="$block
$(clean "$counts")"
    [ -n "$needs" ] && block="$block
Needs: $(clean "$needs")"
    block="$block
$END_MARK"
    if [ -n "$human" ]; then new="$block

$human"; else new="$block"; fi
    write_comment "$sel" "$new" "$sid" || { echo "orca worktree set failed for $sel" >&2; exit 1; }
    echo "COMMENT     $sel  $verdict${sid:+ (status $sid)}"
    ;;
  sweep)
    wts="$("$ORCA" worktree list --json 2>/dev/null)" || { echo "orca worktree list failed; sweep skipped"; exit 1; }
    # path <tab> current status <tab> recorded status, for marked comments only
    printf '%s' "$wts" | jq -r '
      .result.worktrees[]
      | select((.isArchived // false) | not)
      | select((.comment // "") | test("<!-- orca-auto v1 "))
      | [.path, (.workspaceStatus // ""), ((.comment | capture("<!-- orca-auto v1 [^>]*status=(?<s>[^ ]+)").s) // "")]
      | @tsv' | while IFS="$(printf '\t')" read -r p now was; do
        [ -n "$p" ] || continue
        if [ "$now" = "$was" ]; then echo "KEEP        $(basename "$p")  status $now unchanged"; continue; fi
        human="$(printf '%s' "$wts" | jq -r --arg p "$p" '.result.worktrees[] | select(.path==$p) | .comment' | strip_block)"
        write_comment "path:$p" "$human"
        echo "STALE       $(basename "$p")  verdict written at $was, card now $now; block removed, human text kept"
      done
    ;;
  *) sed -n '2,34p' "$0"; exit 2 ;;
esac
exit 0
