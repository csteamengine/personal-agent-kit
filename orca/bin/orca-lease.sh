#!/bin/bash
# orca-lease.sh: named-resource lease for parallel Orca agent sessions.
# N slots, strict FIFO queue, dead-holder reaping, wake-by-terminal.
#
# Use it for anything only N sessions may use at once: one shared browser
# profile, a local backend stack, a GPU, a rate-limited account.
#
# Usage:
#   acquire --resource <r> --worktree <path>   exit 0 = granted; exit 10 = queued
#   release --resource <r> --worktree <path>   drop your slot (or leave the queue), promote waiters
#   leave   --resource <r> --worktree <path>   leave the queue without ever holding
#   status  --resource <r>                     holders (with port) and queue
#   reap    --resource <r>                     drop stale holders, promote waiters
#   profile --resource <r> --worktree <path>   print that worktree's per-session profile dir
#
# Resource config: $ORCA_KIT_CONFIG/leases/<r>.conf (shell syntax, all optional):
#   CAP=1             slots
#   GRACE=900         seconds a holder may sit unused before it is reaped
#   PORTS=""          space-separated ports to hand out, one per holder ("" = none)
#   BUSY_PATTERN=""   pgrep -f pattern; a holder is busy while it matches.
#                     "{profile}" is replaced with the holder's profile dir.
#   BUSY_CMD=""       alternative to BUSY_PATTERN: a command run with the holder's
#                     path as $1; exit 0 = busy. Wins over BUSY_PATTERN.
#   BUSY_PORT=""      alternative: busy while something listens on this TCP port.
#   WAKE_CMD=""       what the woken session should run; default re-runs acquire.
#   NAME="<r> lease"  human name used in messages.
# With no busy check configured, a holder counts as idle and is reaped after GRACE.
#
# The browser resource ships defaults (see browser-queue.sh): capacity 1, the
# stock chrome-devtools-mcp profile as the busy check.
#
# Ordering: a sequence number is assigned inside an atomic mkdir mutex, so the
# queue order IS the order the mutex was won. A freed slot goes straight to the
# queue head inside the same mutex, so nobody can jump in between.
# Stale holder: workspace gone from `orca worktree list`, or not busy for longer
# than GRACE since grant or last seen busy. Orca unreachable: everyone counts as
# alive, so a session is never dropped on a guess.
# Stores workspace paths, ports and epoch times only.
# Exit: 0 ok/granted, 10 queued, 1 error, 2 bad arguments.
#
# Stock Orca commands used: worktree list, terminal list, terminal send.
set -uo pipefail

ORCA="${ORCA_BIN:-orca}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${ORCA_KIT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-kit/orca}"
STATE_ROOT="${ORCA_KIT_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-kit/orca}"
TAB="$(printf '\t')"

cmd="${1:-}"; shift || true
RES=""; WT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --resource) RES="${2:-}"; shift 2 ;;
    --worktree) WT="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
usage() { sed -n '6,13p' "$0" >&2; exit 2; }

case "$RES" in ''|*[!A-Za-z0-9._-]*) echo "--resource must be a simple name ([A-Za-z0-9._-])" >&2; usage ;; esac
case "$cmd" in
  acquire|release|leave|profile) [ -n "$WT" ] || { echo "$cmd needs --worktree <path>" >&2; exit 2; } ;;
  status|reap) ;;
  *) usage ;;
esac

# Defaults, then the browser resource's built-ins, then the config file, then env.
CAP=1; GRACE=900; PORTS=""; BUSY_PATTERN=""; BUSY_CMD=""; BUSY_PORT=""; WAKE_CMD=""; NAME="$RES lease"
if [ "$RES" = browser ]; then
  NAME="browser lock"
  BUSY_PATTERN="user-data-dir=.*chrome-devtools-mcp/chrome-profile"
  WAKE_CMD="$HERE/browser-queue.sh acquire --worktree"
fi
# shellcheck disable=SC1090
[ -f "$CONFIG/leases/$RES.conf" ] && . "$CONFIG/leases/$RES.conf"
CAP="${LEASE_CAP:-$CAP}"; GRACE="${LEASE_GRACE:-$GRACE}"; PORTS="${LEASE_PORTS-$PORTS}"
BUSY_PATTERN="${LEASE_BUSY_PATTERN-$BUSY_PATTERN}"; BUSY_CMD="${LEASE_BUSY_CMD-$BUSY_CMD}"; BUSY_PORT="${LEASE_BUSY_PORT-$BUSY_PORT}"
[ -n "$WAKE_CMD" ] || WAKE_CMD="$HERE/orca-lease.sh acquire --resource $RES --worktree"
case "$CAP" in ''|*[!0-9]*|0) echo "capacity must be a positive integer" >&2; exit 2 ;; esac
case "$GRACE" in ''|*[!0-9]*) echo "grace must be a whole number of seconds" >&2; exit 2 ;; esac

STATE="$STATE_ROOT/leases/$RES"
PROFILES="${LEASE_PROFILE_ROOT:-$STATE/profiles}"

# Profile dir for a worktree: basename plus a hash of the full path, so two
# worktrees with the same name never share one. chrome-mcp-per-worktree.sh calls `profile`.
profile_dir() {
  local b h
  b="$(basename "$1" | tr -d '\n' | tr -c 'A-Za-z0-9._-' '_' | cut -c1-40)"
  h="$(printf '%s' "$1" | (shasum 2>/dev/null || sha1sum) | cut -c1-8)"
  printf '%s/%s-%s' "$PROFILES" "$b" "$h"
}
if [ "$cmd" = profile ]; then profile_dir "$WT"; echo; exit 0; fi

MUTEX="$STATE/mutex"
HOLDERS="$STATE/holder"  # lines: path<TAB>acquiredAt<TAB>seenAt<TAB>port
QUEUE="$STATE/queue"     # lines: seq<TAB>path<TAB>joinedAt
SEQ="$STATE/seq"
LOG="$STATE/events.log"  # paths, verbs, ports and times only
NOTIFY=""                # workspaces to alert once the mutex is released, one per line

mkdir -p "$STATE"; touch "$QUEUE" "$HOLDERS" "$LOG"; [ -s "$SEQ" ] || echo 0 > "$SEQ"
now() { date +%s; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || now; }
log() { echo "$(now)${TAB}$*" >> "$LOG"; }

lock() {
  local i=0
  until mkdir "$MUTEX" 2>/dev/null; do
    if [ -d "$MUTEX" ] && [ $(( $(now) - $(mtime "$MUTEX") )) -gt 30 ]; then
      rmdir "$MUTEX" 2>/dev/null; log "mutex-broken"; continue
    fi
    i=$((i+1)); [ "$i" -gt 400 ] && { echo "orca-lease: mutex busy for 20 s" >&2; exit 1; }
    sleep 0.05
  done
}
unlock() { rmdir "$MUTEX" 2>/dev/null; }

# Unknown (Orca down, odd JSON) counts as alive: never drop a session we cannot see.
alive() {
  local out
  out="$("$ORCA" worktree list --json 2>/dev/null)" || return 0
  printf '%s' "$out" | jq -e --arg p "$1" \
    '[.result.worktrees[]? | select((.isArchived // false) | not) | .path] | index($p) != null' >/dev/null 2>&1 \
    && return 0
  printf '%s' "$out" | jq -e '.result.worktrees' >/dev/null 2>&1 && return 1 || return 0
}

# Is this holder actually using the resource right now?
busy() {  # path
  if [ -n "$BUSY_CMD" ]; then
    sh -c "$BUSY_CMD" busy-check "$1" >/dev/null 2>&1
  elif [ -n "$BUSY_PATTERN" ]; then
    local pd pat; pd="$(profile_dir "$1")"; pat="${BUSY_PATTERN//"{profile}"/$pd}"
    pgrep -f "$pat" >/dev/null 2>&1
  elif [ -n "$BUSY_PORT" ]; then
    lsof -nP -iTCP:"$BUSY_PORT" -sTCP:LISTEN >/dev/null 2>&1
  else
    return 1
  fi
}

port_listening() { [ "${LEASE_PORT_PROBE:-1}" = 1 ] && lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
# First port not held by another holder and not already listening. Empty if none.
free_port() {
  local p
  [ -n "$PORTS" ] || return 0
  for p in $PORTS; do
    awk -F'\t' -v p="$p" '$4==p{f=1} END{exit !f}' "$HOLDERS" && continue
    port_listening "$p" && continue
    printf '%s' "$p"; return 0
  done
}

nholders() { grep -c . "$HOLDERS" | tr -d ' '; }
is_holder() { awk -F'\t' -v p="$1" '$1==p{f=1} END{exit !f}' "$HOLDERS"; }
holder_port() { awk -F'\t' -v p="$1" '$1==p{print $4; exit}' "$HOLDERS"; }
drop_holder() { awk -F'\t' -v p="$1" '$1!=p' "$HOLDERS" > "$HOLDERS.tmp" && mv "$HOLDERS.tmp" "$HOLDERS"; }
add_holder() { printf '%s\t%s\t0\t%s\n' "$1" "$(now)" "${2:-}" >> "$HOLDERS"; }
in_queue() { awk -F'\t' -v p="$1" '$2==p{f=1} END{exit !f}' "$QUEUE"; }
drop_from_queue() { awk -F'\t' -v p="$1" '$2!=p' "$QUEUE" > "$QUEUE.tmp" && mv "$QUEUE.tmp" "$QUEUE"; }
drop_queue_head() { awk 'NR>1' "$QUEUE" > "$QUEUE.tmp" && mv "$QUEUE.tmp" "$QUEUE"; }
position() { awk -F'\t' -v p="$1" '$2==p{print NR; exit}' "$QUEUE"; }

reap() {
  local h acq seen port t last keep=""
  t=$(now)
  while IFS="$TAB" read -r h acq seen port; do
    [ -n "$h" ] || continue
    if ! alive "$h"; then
      log "reaped-gone${TAB}$h"; echo "reaped stale holder (workspace gone): $h"; continue
    fi
    if busy "$h"; then keep="${keep}${h}${TAB}${acq}${TAB}${t}${TAB}${port}
"; continue; fi
    last=$acq; [ "${seen:-0}" -gt "$last" ] && last=$seen
    if [ $(( t - last )) -gt "$GRACE" ]; then
      log "reaped-idle${TAB}$h"; echo "reaped stale holder (not in use for over ${GRACE}s): $h"; continue
    fi
    keep="${keep}${h}${TAB}${acq}${TAB}${seen:-0}${TAB}${port}
"
  done < "$HOLDERS"
  printf '%s' "$keep" > "$HOLDERS"
}

# Fill free slots from the queue head. Dead waiters are dropped, not skipped over later.
promote() {
  local seq w j p
  while [ "$(nholders)" -lt "$CAP" ] && [ -s "$QUEUE" ]; do
    IFS="$TAB" read -r seq w j < "$QUEUE"
    if ! alive "$w"; then
      drop_queue_head
      log "dropped-dead-waiter${TAB}$w"; echo "dropped waiter whose workspace is gone: $w"; continue
    fi
    p=""
    if [ -n "$PORTS" ]; then
      p="$(free_port)"
      if [ -z "$p" ]; then echo "no free port in: $PORTS; head of queue stays queued" >&2; log "no-port${TAB}$w"; return 0; fi
    fi
    drop_queue_head
    add_holder "$w" "$p"; log "promoted${TAB}$w${TAB}port=${p:--}"
    NOTIFY="${NOTIFY}${w}
"
  done
}

# Wake the promoted session by typing into its agent terminal. A queued session
# has ended its turn; typed input starts a new one.
notify() {
  local w="$1" handle msg
  handle="$("$ORCA" terminal list --worktree "path:$w" --json 2>/dev/null | jq -r '
      [.. | objects | select(has("handle"))] as $t
      | (([$t[] | select(tostring | test("claude|codex|agent"; "i"))] + $t) | first | .handle) // empty' 2>/dev/null)"
  msg="The $NAME is now yours (orca-lease, $RES). Run: $WAKE_CMD $w and then continue the work you queued for."
  if [ -n "$handle" ] && "$ORCA" terminal send --terminal "$handle" --text "$msg" --enter --json >/dev/null 2>&1; then
    log "notified${TAB}$w"; echo "alerted next holder: $w"
  else
    log "notify-failed${TAB}$w"
    echo "$NAME handed to $w, but its terminal could not be reached; it is reaped after ${GRACE}s unused" >&2
  fi
}

finish() {
  local w
  unlock
  printf '%s' "$NOTIFY" | awk 'NF && !seen[$0]++' | while IFS= read -r w; do notify "$w"; done
}
granted() {  # path
  local p; p="$(holder_port "$1")"
  echo "GRANTED: the $NAME is yours. Release it when the work ends, pass, fail or cancelled."
  [ -n "$p" ] && echo "PORT=$p"
  echo "PROFILE=$(profile_dir "$1")"
}

lock; trap 'unlock' EXIT
case "$cmd" in
  acquire)
    reap >/dev/null; promote
    if ! is_holder "$WT" && ! in_queue "$WT" && [ "$(nholders)" -lt "$CAP" ] && [ ! -s "$QUEUE" ]; then
      p=""
      if [ -n "$PORTS" ]; then p="$(free_port)"; fi
      if [ -z "$PORTS" ] || [ -n "$p" ]; then add_holder "$WT" "$p"; log "acquired${TAB}$WT${TAB}port=${p:--}"
      else echo "no free port in: $PORTS; queued instead" >&2; fi
    fi
    if is_holder "$WT"; then
      NOTIFY="$(printf '%s' "$NOTIFY" | awk -v w="$WT" '$0!=w')
"   # promoted to ourselves: nobody to alert
      trap - EXIT; finish; granted "$WT"; exit 0
    fi
    if ! in_queue "$WT"; then
      n=$(( $(cat "$SEQ") + 1 )); echo "$n" > "$SEQ"
      printf '%s\t%s\t%s\n' "$n" "$WT" "$(now)" >> "$QUEUE"; log "queued${TAB}$WT${TAB}seq=$n"
    fi
    pos="$(position "$WT")"; total="$(wc -l < "$QUEUE" | tr -d ' ')"
    hs="$(cut -f1 "$HOLDERS" | awk 'NF' | paste -sd ',' - | sed 's/,/, /g')"
    ahead="none"; [ "$pos" -gt 1 ] && ahead="$(awk -F'\t' -v n=$((pos-1)) 'NR==n{print $2}' "$QUEUE")"
    trap - EXIT; finish
    echo "You will be alerted in this terminal when it is your turn."
    echo "QUEUED: position $pos of $total. Holder(s), $(nholders) of $CAP slots: ${hs:-none}. Directly ahead of you: $ahead."
    exit 10 ;;
  release|leave)
    if is_holder "$WT"; then drop_holder "$WT"; log "released${TAB}$WT"; echo "released"
    elif in_queue "$WT"; then drop_from_queue "$WT"; log "left${TAB}$WT"; echo "left the queue"
    else echo "not holding and not queued; nothing to do"; fi
    reap; promote; trap - EXIT; finish; exit 0 ;;
  reap)
    reap; promote; trap - EXIT; finish; exit 0 ;;
  status)
    echo "resource: $RES, $(nholders) of $CAP slots held"
    awk -F'\t' 'NF{ if ($4!="") printf "holder: %s (port %s)\n", $1, $4; else printf "holder: %s\n", $1 }' "$HOLDERS"
    [ "$(nholders)" -gt 0 ] || echo "holder: none"
    awk -F'\t' '{printf "  %d. %s (seq %s)\n", NR, $2, $1}' "$QUEUE"
    exit 0 ;;
esac
