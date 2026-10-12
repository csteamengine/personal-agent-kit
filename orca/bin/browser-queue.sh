#!/bin/bash
# browser-queue.sh: the browser lease, so parallel agent sessions doing browser
# QA never drive the same Chrome at once. Thin wrapper over
# orca-lease.sh --resource browser.
#
# Usage (every command takes the session's Orca workspace path, i.e. its worktree root):
#   acquire --worktree <path>   exit 0 = yours (prints PROFILE=, and PORT= if ports are configured); exit 10 = queued
#   release --worktree <path>   drop your slot (or leave the queue), hand it to the next live waiter
#   leave   --worktree <path>   leave the queue without ever holding
#   status                      print holders and queue
#   reap                        drop stale holders, promote waiters
#   profile --worktree <path>   print the per-worktree Chrome profile dir
#
# Two modes:
#   shared (default)  capacity 1. Every session uses the stock chrome-devtools-mcp
#                     profile; busy while a Chrome runs on it.
#   per-session       chrome-mcp-per-worktree.sh is your MCP command, so each
#                     session gets its own profile. Put this in
#                     $ORCA_KIT_CONFIG/leases/browser.conf:
#                       CAP=3
#                       PORTS="8080 8081 8082"
#                       BUSY_PATTERN="user-data-dir={profile}"
# Exit: 0 ok/granted, 10 queued, 1 error, 2 bad arguments.
cmd="${1:-}"; shift || true
exec "${ORCA_LEASE_SH:-$(cd "$(dirname "$0")" && pwd)/orca-lease.sh}" "$cmd" --resource browser "$@"
