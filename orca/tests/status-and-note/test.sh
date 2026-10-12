#!/bin/bash
# orca-status.sh and orca-card-note.sh against a fake one-card orca.
T="$(cd "$(dirname "$0")" && pwd)"; BIN="$(cd "$T/../../bin" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export ORCA_BIN="$T/fake-orca" FAKE_DIR="$W/fake" ORCA_KIT_CONFIG="$W/config"
mkdir -p "$W/fake"
S="$BIN/orca-status.sh"; N="$BIN/orca-card-note.sh"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }

ok "built-in label resolves case-insensitively" '[ "$($S id in review)" = in-review ]'
ok "unknown label exits 1" '$S id Mergeable >/dev/null 2>&1; [ $? -eq 1 ]'
echo status-8 > "$W/fake/status"
$S learn --worktree path:/w/A Mergeable >/dev/null
ok "learn records the card's current id" '[ "$($S id mergeable)" = status-8 ]'
echo status-9 > "$W/fake/status"; $S learn --worktree path:/w/A Mergeable >/dev/null
ok "learn again replaces, never duplicates" '[ "$($S id Mergeable)" = status-9 ] && [ "$(grep -ci mergeable $W/config/statuses.tsv)" = 1 ]'
$S set --worktree path:/w/A "In progress" >/dev/null
ok "set writes the resolved id" '[ "$(cat $W/fake/status)" = in-progress ]'
$S set --worktree path:/w/A Nope >/dev/null 2>&1
ok "set with unknown label falls back to In review" '[ "$(cat $W/fake/status)" = in-review ]'

printf 'my own text' > "$W/fake/comment"
$N set --worktree path:/w/A --src test --verdict "CI green" --counts "3 checks" --status-label Mergeable >/dev/null
ok "note: block on top, human text kept, status set in same call" 'head -1 $W/fake/comment | grep -q "status=status-9" && tail -1 $W/fake/comment | grep -qx "my own text" && [ "$(cat $W/fake/status)" = status-9 ]'
ok "note: unknown verdict exits 2" '$N set --worktree path:/w/A --src t --verdict "Whatever" >/dev/null 2>&1; [ $? -eq 2 ]'
ok "note: --> in counts cannot break the fence" '$N set --worktree path:/w/A --src t --verdict Blocked --counts "a --> b" >/dev/null; [ "$(grep -c -- "-->" $W/fake/comment)" = 2 ]'
$N sweep >/dev/null
ok "sweep keeps a block whose status still matches" 'grep -q "orca-auto v1" $W/fake/comment'
echo completed > "$W/fake/status"; $N sweep >/dev/null
ok "sweep removes a stale block, keeps human text" '[ "$(cat $W/fake/comment)" = "my own text" ]'

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
