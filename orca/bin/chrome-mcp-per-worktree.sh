#!/bin/bash
# chrome-mcp-per-worktree.sh: drop-in MCP `command` for chrome-devtools-mcp that
# gives every agent session its own Chrome profile, keyed by its Orca worktree,
# so parallel browser sessions never collide on one profile.
#
# Register it in your agent's MCP config in place of `npx chrome-devtools-mcp`,
# e.g. for Claude Code: claude mcp add chrome-devtools -- /path/to/chrome-mcp-per-worktree.sh
# Then switch the browser lease to per-session mode (see browser-queue.sh).
# Some managed MCP allowlists reject a wrapper script; if yours does, stay in
# shared mode.
#
# Profile dir: `orca-lease.sh profile --resource browser --worktree <wt>`. Wiped
# on every launch (same freshness as --isolated, no unbounded growth). If a
# Chrome is already running on it (a second session in the same worktree), the
# first free <dir>-2 ... <dir>-9 is used instead, so a live browser is never
# wiped. Same if another live chrome-devtools-mcp owns it (<dir>.owner holds its pid).
# Worktree: ORCA_WORKTREE_ID (form "<repoId>::<path>", set by Orca in its
# terminals), else the git toplevel of the cwd, else the cwd.
# Chrome runs with --remote-debugging-port=0, so a helper can reach this browser
# through the profile's DevToolsActivePort file.
# CHROME_MCP_DISABLE_WEB_SECURITY=1 adds --disable-web-security (a local CORS
# workaround); off by default, never use it against a real site.
# CHROME_MCP_SHARED_PROFILE=1 falls back to the stock single shared profile.
# Logs (paths, pids, times only): <state>/leases/browser/wrapper.log
# stdout is the MCP stdio channel: this script must print nothing to it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="${ORCA_KIT_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-kit/orca}/leases/browser"
LEASE="${ORCA_LEASE_SH:-$HERE/orca-lease.sh}"
MCP_PKG="${CHROME_MCP_PKG:-chrome-devtools-mcp@latest}"
mkdir -p "$STATE"
wlog() { printf '%s\t%s\n' "$(date +%s)" "$*" >> "$STATE/wrapper.log"; }

if [ "${CHROME_MCP_SHARED_PROFILE:-0}" = 1 ]; then
  wlog "shared-profile	pid=$$"
  exec npx -y "$MCP_PKG" "$@"
fi

wt=""
case "${ORCA_WORKTREE_ID:-}" in *::*) wt="${ORCA_WORKTREE_ID#*::}" ;; esac
src="ORCA_WORKTREE_ID"
if [ -z "$wt" ] || [ ! -d "$wt" ]; then
  wt="$(git rev-parse --show-toplevel 2>/dev/null)"; src="git-toplevel"
  [ -n "$wt" ] || { wt="$PWD"; src="cwd"; }
fi

base="$("$LEASE" profile --resource browser --worktree "$wt" 2>/dev/null)"
[ -n "$base" ] || { wlog "profile-lookup-failed	$wt"; base="$STATE/profiles/unkeyed-$$"; }
# Taken if a Chrome runs on it, or another live MCP server owns it. Chrome starts
# lazily on the first tool call, so the owner file is what stops two sessions in
# one worktree, launched before either opened a page, from sharing a profile.
taken() {
  local o
  pgrep -f "user-data-dir=$1( |$)" >/dev/null 2>&1 && return 0
  o="$(cat "$1.owner" 2>/dev/null)"
  [ -n "$o" ] && [ "$o" != "$$" ] && ps -p "$o" -o command= 2>/dev/null | grep -q chrome-devtools-mcp
}
dir="$base"; i=2
while taken "$dir"; do
  [ "$i" -gt 9 ] && { dir="$base-$$"; break; }
  dir="$base-$i"; i=$((i+1))
done
rm -rf "$dir"; mkdir -p "$dir"; echo "$$" > "$dir.owner"
wlog "launch	worktree=$wt	source=$src	profile=$dir	pid=$$"

args=(--userDataDir "$dir" --chromeArg=--remote-debugging-port=0)
[ "${CHROME_MCP_DISABLE_WEB_SECURITY:-0}" = 1 ] && args+=(--chromeArg=--disable-web-security)
exec npx -y "$MCP_PKG" "${args[@]}" "$@"
