#!/bin/bash
# scratch-tracker.sh: create and bound-check a per-worktree session tracker, so
# work that spans more than one agent session survives the session.
#
# Layout: <worktree root>/.scratch/<topic>/TRACKER.md, bulk output in
# <topic>/notes/, rolled-over trackers in <topic>/archive/. The scratch lives in
# the worktree's own root, so links to it open in the same Orca workspace, and it
# dies with the worktree on purpose: copy anything worth keeping somewhere
# durable first. Add `.scratch/` to your global gitignore.
#
# Usage:
#   init  <topic> [--title <text>]   create the tracker if missing; print its path
#   path  <topic>                    print the tracker path
#   check <topic>                    report section sizes against the bounds; exit 1 if over
#   roll  <topic>                    copy to archive/TRACKER-<YYYY-MM-DD>.md; you then rewrite it
#
# Topic: a short kebab slug, ticket key first when there is one. Never a date in
# a folder name, nothing at the .scratch/ root.
# Bounds: Now 3 lines, Open questions 7, Findings 15, whole file 150 lines.
# User corrections is never pruned.
set -uo pipefail

cmd="${1:-}"; topic="${2:-}"; shift 2 2>/dev/null || true
title=""
while [ $# -gt 0 ]; do case "$1" in --title) title="${2:-}"; shift 2 ;; *) echo "unknown argument: $1" >&2; exit 2 ;; esac; done
case "$topic" in ''|*/*|.*) echo "topic must be a plain folder name" >&2; exit 2 ;; esac
printf '%s' "$topic" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' && { echo "no dates in topic names" >&2; exit 2; }

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not inside a git worktree" >&2; exit 1; }
dir="$root/.scratch/$topic"; T="$dir/TRACKER.md"

count() {  # section heading -> number of non-blank lines under it
  awk -v h="## $1" '$0==h{on=1; next} /^## /{on=0} on && NF' "$T" | wc -l | tr -d ' '
}

case "$cmd" in
  init)
    if [ ! -f "$T" ]; then
      mkdir -p "$dir/notes"
      cat > "$T" <<EOF
# ${title:-$topic}

Updated: $(date +%Y-%m-%d). Ticket: none. Durable doc: none.

## Now

## Decisions

## User corrections

## Open questions

## Findings
EOF
    fi
    echo "$T" ;;
  path) echo "$T" ;;
  check)
    [ -f "$T" ] || { echo "no tracker at $T" >&2; exit 1; }
    over=0
    for pair in "Now:3" "Open questions:7" "Findings:15"; do
      s="${pair%%:*}"; max="${pair##*:}"; n="$(count "$s")"
      if [ "$n" -gt "$max" ]; then echo "OVER  $s: $n of $max"; over=1; else echo "ok    $s: $n of $max"; fi
    done
    total="$(wc -l < "$T" | tr -d ' ')"
    if [ "$total" -gt 150 ]; then echo "OVER  file: $total of 150 lines, roll over"; over=1; else echo "ok    file: $total of 150 lines"; fi
    exit "$over" ;;
  roll)
    [ -f "$T" ] || { echo "no tracker at $T" >&2; exit 1; }
    mkdir -p "$dir/archive"; a="$dir/archive/TRACKER-$(date +%Y-%m-%d).md"
    [ -e "$a" ] && a="$dir/archive/TRACKER-$(date +%Y-%m-%d-%H%M).md"
    cp "$T" "$a"
    echo "archived to $a. Now rewrite $T, carrying forward every user correction, decisions still in force, and open questions." ;;
  *) sed -n '2,21p' "$0" >&2; exit 2 ;;
esac
