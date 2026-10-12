#!/bin/bash
# orca-lease.sh behavior against a fake orca. Touches nothing real: state, config
# and profiles live in a temp dir that is removed at the end.
# Run: bash tests/orca-lease/test.sh   (needs jq, lsof, python3 for one port test)
T="$(cd "$(dirname "$0")" && pwd)"; BIN="$(cd "$T/../../bin" && pwd)"
L="$BIN/orca-lease.sh"; Q="$BIN/browser-queue.sh"
W="$(mktemp -d)"
export ORCA_BIN="$T/fake-orca" FAKE_DIR="$W/fake" ORCA_KIT_STATE="$W/state" ORCA_KIT_CONFIG="$W/config"
pass=0; fail=0; PIDS=""
ok() { if eval "$2"; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }
S() { echo "$W/state/leases/$1"; }
reset() { rm -rf "$W/state" "$W/fake" "$W/config"; mkdir -p "$W/fake" "$W/config/leases"; printf '/w/%s\n' A B C D E F G H I > "$W/fake/alive"; : > "$W/fake/sends"; }
pool() { printf 'CAP=3\nPORTS="18081 18082 18083 18084 18085"\nBUSY_PATTERN="user-data-dir={profile}"\nGRACE=%s\n' "${1:-900}" > "$W/config/leases/browser.conf"; }
B() { $L "$1" --resource browser --worktree "$2"; }
holders() { cut -f1 "$(S browser)/holder" | awk NF | sort | tr '\n' ' '; }
portof() { awk -F'\t' -v p="$1" '$1==p{print $4}' "$(S browser)/holder"; }
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -rf "$W"; }
trap cleanup EXIT

reset; pool
for w in A B C; do B acquire /w/$w > "$W/out.$w"; echo $? > "$W/rc.$w"; done
ok "3 slots: A, B, C all granted" '[ "$(cat $W/rc.A $W/rc.B $W/rc.C | sort -u)" = 0 ] && [ "$(holders)" = "/w/A /w/B /w/C " ]'
ok "each holder gets a distinct port, printed as PORT=" '[ "$(portof /w/A) $(portof /w/B) $(portof /w/C)" = "18081 18082 18083" ] && grep -qx "PORT=18082" "$W/out.B"'
ok "PROFILE= printed and matches the profile command" 'grep -qx "PROFILE=$(B profile /w/A)" "$W/out.A"'
B acquire /w/D > "$W/out.D"; rc=$?
ok "4th joiner queued at position 1, told 3 of 3 held" '[ $rc -eq 10 ] && grep -q "position 1 of 1. Holder(s), 3 of 3 slots" "$W/out.D"'
B release /w/B >/dev/null
ok "release B: D promoted into the freed slot, reuses port 18082" '[ "$(holders)" = "/w/A /w/C /w/D " ] && [ "$(portof /w/D)" = 18082 ]'
ok "D alerted via its agent terminal, not the plain shell" '[ "$(tail -1 $W/fake/sends)" = h-D ]'
B acquire /w/D > "$W/out.D2"
ok "D re-acquire after the alert confirms with its port" '[ $? -eq 0 ] && grep -qx "PORT=18082" "$W/out.D2"'

reset; pool
python3 -m http.server 18081 --bind 127.0.0.1 >/dev/null 2>&1 & SRV=$!; PIDS="$PIDS $SRV"; sleep 1
B acquire /w/A >/dev/null
ok "port already listening is skipped" '[ "$(portof /w/A)" = 18082 ]'
kill $SRV 2>/dev/null; wait $SRV 2>/dev/null
reset; pool; LEASE_PORTS="18091" B acquire /w/A >/dev/null; LEASE_PORTS="18091" B acquire /w/B > "$W/out.B" 2> "$W/err.B"; rc=$?
ok "no free port: queued, not granted without a port" '[ $rc -eq 10 ] && grep -q "no free port" "$W/err.B"'

reset; pool 2
B acquire /w/A >/dev/null; B acquire /w/B >/dev/null
( exec -a "fakechrome --user-data-dir=$(B profile /w/A) --x" sleep 300 ) & PIDS="$PIDS $!"; sleep 3
B acquire /w/E >/dev/null
ok "per-slot reaping: A (browser on its profile) kept, idle B reaped" '[ "$(holders)" = "/w/A /w/E " ]'

reset; pool
B acquire /w/A >/dev/null; B acquire /w/B >/dev/null; B acquire /w/C >/dev/null
grep -v '^/w/B$' "$W/fake/alive" > "$W/fake/a2" && mv "$W/fake/a2" "$W/fake/alive"
B acquire /w/D >/dev/null; rc=$?
ok "holder whose workspace is gone frees its slot for a new joiner" '[ $rc -eq 0 ] && [ "$(holders)" = "/w/A /w/C /w/D " ]'

reset; pool; bad=""
for r in $(seq 1 10); do
  jp=""; for w in A B C D E F G H; do ( B acquire /w/$w >/dev/null ) & jp="$jp $!"; done; wait $jp
  nh=$(awk NF "$(S browser)/holder" | wc -l | tr -d ' '); nq=$(wc -l < "$(S browser)/queue" | tr -d ' ')
  up=$(cut -f4 "$(S browser)/holder" | awk NF | sort -u | wc -l | tr -d ' ')
  all=$( { cut -f1 "$(S browser)/holder"; cut -f2 "$(S browser)/queue"; } | awk NF | sort -u | wc -l | tr -d ' ')
  [ "$nh" = 3 ] && [ "$nq" = 5 ] && [ "$up" = 3 ] && [ "$all" = 8 ] || { echo "round $r bad: holders=$nh queue=$nq ports=$up distinct=$all"; bad=1; }
  for w in A B C D E F G H; do B leave /w/$w >/dev/null; done
done
ok "10 rounds x 8 racing joiners, 3 slots: 3 hold distinct ports, 5 queue, none lost" '[ -z "$bad" ]'

ok "profile dirs differ for same-named worktrees at different paths" '[ "$(B profile /x/repo/feat)" != "$(B profile /y/repo/feat)" ] && [ "$(B profile /x/repo/feat)" = "$(B profile /x/repo/feat)" ]'

reset
printf 'CAP=1\nGRACE=2\nBUSY_PATTERN="sleep 3029"\n' > "$W/config/leases/stack.conf"
K() { $L "$1" --resource stack --worktree "$2"; }
K acquire /w/A > "$W/out.kA"; ra=$?; K acquire /w/B > "$W/out.kB"; rb=$?
ok "custom resource: capacity 1, second queued, no PORT handed out" '[ $ra -eq 0 ] && [ $rb -eq 10 ] && ! grep -q PORT= "$W/out.kA"'
ok "custom resource: state separate from the browser lease" '[ ! -e "$(S browser)/holder" ] && [ -s "$(S stack)/holder" ]'
( exec -a "java sleep 3029" sleep 300 ) & JP=$!; PIDS="$PIDS $JP"; sleep 3
$L reap --resource stack >/dev/null
ok "custom resource: holder kept while its busy pattern runs" '[ "$($L status --resource stack | sed -n "s/^holder: //p")" = /w/A ]'
kill $JP; wait $JP 2>/dev/null; sleep 3; $L reap --resource stack >/dev/null
ok "custom resource: busy gone past grace -> reaped, B promoted and alerted" '[ "$($L status --resource stack | sed -n "s/^holder: //p")" = /w/B ] && [ "$(tail -1 $W/fake/sends)" = h-B ]'
ok "wake prompt tells B to re-run acquire for that resource" 'grep -q "^h-B" "$W/fake/sends"'

reset
printf 'GRACE=2\nBUSY_CMD="[ -f %s/fake/busy-\\$(basename \\"\\$1\\") ]"\n' "$W" > "$W/config/leases/cmd.conf"
$L acquire --resource cmd --worktree /w/A >/dev/null; $L acquire --resource cmd --worktree /w/B >/dev/null
touch "$W/fake/busy-A"; sleep 3; $L reap --resource cmd >/dev/null
ok "BUSY_CMD exit 0 keeps the holder" '[ "$($L status --resource cmd | sed -n "s/^holder: //p")" = /w/A ]'

reset
B acquire /w/A > "$W/out.sA"; B acquire /w/B > /dev/null; rc=$?
ok "browser with no config: shared mode, capacity 1, second joiner queued" '[ $rc -eq 10 ] && grep -q "^GRANTED" "$W/out.sA"'
ok "browser-queue.sh forwards to the browser lease" '$Q status | grep -q "resource: browser, 1 of 1"'

ok "bad resource name rejected with exit 2" '$L status --resource "../x" >/dev/null 2>&1; [ $? -eq 2 ]'

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
