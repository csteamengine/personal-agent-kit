#!/bin/bash
# orca-status.sh: set an Orca workspace's board status by LABEL, on stock Orca.
#
# Why: `orca worktree set --workspace-status` takes an id. The four built-in
# columns have fixed ids (todo, in-progress, in-review, completed), but a column
# you add in Settings gets a generated id (e.g. status-7), and stock Orca has no
# CLI command that lists them. Never read or edit orca-data.json for this: the
# app keeps board state in memory and its storage format changes between
# releases. Instead this script keeps a small label->id map you teach it once.
#
# Usage:
#   id      <label>                          print the id for a label; exit 1 if unknown
#   set     --worktree <sel> <label> [--fallback <label>]
#                                            set the card's status; unknown label falls
#                                            back to --fallback (default: "In review")
#   learn   --worktree <sel> <label>         record the card's CURRENT status id under
#                                            <label>. Drag any card into the column in the
#                                            UI first, then run this from that workspace.
#   current [--worktree <sel>]               print the card's current status id
#   list                                     print every known label and id
#
# <sel> is any Orca worktree selector (path:<root>, id:<id>, ...). Omit
# --worktree on `current` to use the enclosing worktree.
# Map file: $ORCA_KIT_CONFIG/statuses.tsv, lines "label<TAB>id", matched
# case-insensitively. Built-in labels are known without it.
# Exit: 0 ok, 1 unknown label or Orca call failed, 2 bad arguments.
#
# Stock Orca commands used: worktree show, worktree current, worktree set.
set -uo pipefail

ORCA="${ORCA_BIN:-orca}"
CONFIG="${ORCA_KIT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-kit/orca}"
MAP="$CONFIG/statuses.tsv"
BUILTIN="Todo	todo
In progress	in-progress
In review	in-review
Done	completed"

cmd="${1:-}"; shift || true
sel=""; fallback="In review"; label=""
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree) sel="${2:-}"; shift 2 ;;
    --fallback) fallback="${2:-}"; shift 2 ;;
    -*) echo "unknown argument: $1" >&2; exit 2 ;;
    *) label="${label:+$label }$1"; shift ;;
  esac
done

known() { { [ -f "$MAP" ] && grep -v '^#' "$MAP"; printf '%s\n' "$BUILTIN"; } | awk -F'\t' 'NF==2'; }
id_of() {
  known | awk -F'\t' -v l="$1" 'tolower($1)==tolower(l){print $2; exit}'
}
card_status() {  # sel -> current status id
  local out
  if [ -n "$1" ]; then out="$("$ORCA" worktree show --worktree "$1" --json 2>/dev/null)"
  else out="$("$ORCA" worktree current --json 2>/dev/null)"; fi
  printf '%s' "$out" | jq -r '.result.worktree.workspaceStatus // empty'
}

case "$cmd" in
  id)
    [ -n "$label" ] || { echo "id needs a label" >&2; exit 2; }
    i="$(id_of "$label")"; [ -n "$i" ] || { echo "unknown status label: $label" >&2; exit 1; }
    echo "$i" ;;
  set)
    [ -n "$sel" ] && [ -n "$label" ] || { echo "set needs --worktree <sel> and a label" >&2; exit 2; }
    i="$(id_of "$label")"
    if [ -z "$i" ]; then
      echo "status '$label' unknown; falling back to '$fallback'" >&2
      i="$(id_of "$fallback")"; [ -n "$i" ] || i="in-review"
    fi
    "$ORCA" worktree set --worktree "$sel" --workspace-status "$i" --json 2>/dev/null \
      | jq -e '.ok == true' >/dev/null 2>&1 || { echo "orca worktree set failed for $sel" >&2; exit 1; }
    echo "$i" ;;
  learn)
    [ -n "$sel" ] && [ -n "$label" ] || { echo "learn needs --worktree <sel> and a label" >&2; exit 2; }
    i="$(card_status "$sel")"; [ -n "$i" ] || { echo "could not read the card's status (orca unreachable?)" >&2; exit 1; }
    mkdir -p "$CONFIG"; touch "$MAP"
    awk -F'\t' -v l="$label" 'tolower($1)!=tolower(l)' "$MAP" > "$MAP.tmp" && mv "$MAP.tmp" "$MAP"
    printf '%s\t%s\n' "$label" "$i" >> "$MAP"
    echo "learned: $label -> $i" ;;
  current)
    i="$(card_status "$sel")"; [ -n "$i" ] || exit 1; echo "$i" ;;
  list)
    known | awk -F'\t' '!seen[tolower($1)]++ {printf "%-24s %s\n", $1, $2}' ;;
  *) sed -n '11,25p' "$0" >&2; exit 2 ;;
esac
