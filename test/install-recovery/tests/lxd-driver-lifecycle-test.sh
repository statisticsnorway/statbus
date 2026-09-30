#!/usr/bin/env bash
# STATBUS-425 M3b review recs 1, 2, 4, behavioural and offline: the real
# helpers in lxd/proc-tree.sh. Every process assertion uses exact PIDs this
# test owns (never pgrep -f), and the whole test runs under an outer watchdog.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
source "$ROOT/test/install-recovery/lxd/proc-tree.sh"
WORK=$(mktemp -d)
wd=""
cleanup() {
    [ -z "$wd" ] || kill "$wd" 2>/dev/null
    if [ -f "$WORK/pids" ]; then while read -r p; do kill -KILL "$p" 2>/dev/null; done < "$WORK/pids"; fi
    kill "${live:-}" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT
( sleep 200; echo "FAIL: test watchdog fired" >&2; kill -TERM $$ ) >/dev/null 2>&1 </dev/null &
wd=$!
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }
alive_count() { local n=0 p; while read -r p; do kill -0 "$p" 2>/dev/null && n=$((n+1)); done < "$1"; echo "$n"; }

# Arc double: the leader exits on TERM but leaves a TERM-ignoring orphan that
# has been reparented; the pids of both are recorded.
cat > "$WORK/arc.sh" <<EOS
#!/usr/bin/env bash
( trap '' TERM; exec sleep 250 ) & orphan=\$!
echo "\$\$" >> "$WORK/pids"; echo "\$orphan" >> "$WORK/pids"
trap 'echo cleaned > "$WORK/cleaned"; exit 1' TERM
while :; do sleep 1; done
EOS

# 1. run_bounded timeout: rc 124, leader's TERM trap ran, orphan (which
#    outlives its exited root) is KILLed too.
: > "$WORK/pids"
rc=0; run_bounded 2 2 "$WORK/arc.log" bash "$WORK/arc.sh" || rc=$?
check "timeout rc" "$rc" 124
check "arc TERM trap ran" "$(cat "$WORK/cleaned" 2>/dev/null)" cleaned
check "no owned process (leader+orphan) survives timeout" "$(alive_count "$WORK/pids")" 0
check "both pids were recorded" "$(wc -l < "$WORK/pids" | tr -d ' ')" 2

# 2. normal exit that leaves a TERM-ignoring background child: child killed, rc preserved.
: > "$WORK/pids"
cat > "$WORK/leaky.sh" <<EOS
#!/usr/bin/env bash
( trap '' TERM; exec sleep 251 ) & echo "\$!" >> "$WORK/pids"
exit 3
EOS
rc=0; run_bounded 30 1 "$WORK/leaky.log" bash "$WORK/leaky.sh" || rc=$?
check "normal exit rc preserved" "$rc" 3
check "leftover orphan killed after normal exit" "$(alive_count "$WORK/pids")" 0

# 3. captured output, plain success.
rc=0; run_bounded 10 1 "$WORK/ok.log" bash -c 'echo hi' || rc=$?
check "plain success rc" "$rc" 0
check "output captured" "$(cat "$WORK/ok.log")" hi

# 4. Signal to the caller: run_bounded returns 143 and empties the group.
: > "$WORK/pids"
( run_bounded 60 2 "$WORK/sig.log" bash "$WORK/arc.sh"; echo "rc=$?" > "$WORK/sig.rc" ) &
sub=$!
w=0; while [ "$(wc -l < "$WORK/pids" | tr -d ' ')" -lt 2 ] && [ "$w" -lt 20 ]; do sleep 1; w=$((w+1)); done
kill -TERM "$sub"
w=0; while kill -0 "$sub" 2>/dev/null && [ "$w" -lt 30 ]; do sleep 1; w=$((w+1)); done
check "signalled run_bounded returned 143" "$(cat "$WORK/sig.rc" 2>/dev/null)" "rc=143"
check "signalled run_bounded left no owned process" "$(alive_count "$WORK/pids")" 0

# 5. stop_group never touches an unrelated live process.
sleep 252 &
bystander=$!
stop_group 999999 1
check "stop_group on a nonexistent group is a no-op success" "$?" 0
check "unrelated process untouched" "$(kill -0 "$bystander" 2>/dev/null && echo alive)" alive
kill "$bystander"; wait "$bystander" 2>/dev/null

# 6. dirlock: live holder not stolen; dead holder reaped; fresh holderless kept.
L="$WORK/lock.d"
sleep 302 &
live=$!
mkdir "$L"; echo "$live x" > "$L/holder"
rc=0; DIRLOCK_POLL_S=1 dirlock_acquire "$L" 2 me || rc=$?
check "live holder not stolen (budget refusal)" "$rc" 1
check "live holder's lock intact" "$(cut -d' ' -f1 "$L/holder")" "$live"
kill "$live"; wait "$live" 2>/dev/null
rc=0; dirlock_acquire "$L" 5 me || rc=$?
check "dead holder reaped and acquired" "$rc" 0
check "new holder recorded" "$(cut -d' ' -f1 "$L/holder")" "$$"
rm -rf "$L"; mkdir "$L"
rc=0; DIRLOCK_POLL_S=1 dirlock_acquire "$L" 2 me || rc=$?
check "fresh holderless dir not reaped" "$rc" 1
rm -rf "$L"

# 7. Stuck reap mutex must not spin forever (the C1 shape). Dead-holder lock
#    plus (a) a mutex held by a LIVE pid: budget must expire, rc 1;
#    (b) a mutex held by a DEAD pid: cleared, lock acquired.
sleep 303 &
mtx_live=$!
mkdir "$L"; echo "999999 dead" > "$L/holder"
mkdir "$L.reap.d"; echo "$mtx_live reap" > "$L.reap.d/holder"
start=$(date +%s); rc=0
DIRLOCK_POLL_S=1 dirlock_acquire "$L" 3 me || rc=$?
check "live reap mutex: budget enforced, refusal" "$rc" 1
check "live reap mutex: refusal is bounded" "$([ $(( $(date +%s) - start )) -le 10 ] && echo y)" y
kill "$mtx_live"; wait "$mtx_live" 2>/dev/null
rc=0; DIRLOCK_POLL_S=1 dirlock_acquire "$L" 10 me || rc=$?
check "dead reap mutex cleared, lock acquired" "$rc" 0

[ "$fails" -eq 0 ] && echo "PASS: lxd driver lifecycle helpers" || exit 1
