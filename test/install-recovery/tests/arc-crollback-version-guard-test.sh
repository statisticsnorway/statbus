#!/usr/bin/env bash
# Behavioral check of the REAL `: "${V_VERSION_2:?...}"` / V_VERSION_3 guard
# statements in c-rollback-resurrection-arc.sh. Scope: only those guard lines
# (extracted verbatim and run in a fresh bash), NOT the arc. An apostrophe in
# the message once paired the two guards across lines and left the V3 guard
# dead; unset/empty V3 must fail at the guard, before any side effect.
set -uo pipefail
SRC=$(cd "$(dirname "$0")/../../.." && pwd)
ARC="$SRC/test/install-recovery/arcs/c-rollback-resurrection-arc.sh"
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2' want '$3'"; fails=$((fails+1)); fi; }

guards=$(grep -n '^: "\${V_VERSION_[23]:?' "$ARC" | cut -d: -f1)
first=$(echo "$guards" | head -n1); last=$(echo "$guards" | tail -n1)
check "both guard statements found" "$(echo "$guards" | wc -l | tr -d ' ')" 2
# Each guard is followed by a sentinel standing in for the first VM side effect.
run_guard() { # args: V2 V3 (use "-" for unset)
    local script
    script="set -u
$(sed -n "${first},${last}p" "$ARC")
echo SIDE_EFFECT"
    local -a envs=()
    [ "$1" = - ] || envs+=("V_VERSION_2=$1")
    [ "$2" = - ] || envs+=("V_VERSION_3=$2")
    env -u V_VERSION_2 -u V_VERSION_3 ${envs[@]+"${envs[@]}"} bash -c "$script" 2>&1
}

out=$(run_guard x -); rc=$?
check "V3 unset (V2 set): guard fails" "$([ "$rc" -ne 0 ] && echo fail)" fail
check "V3 unset: no side effect reached" "$(echo "$out" | grep -c SIDE_EFFECT)" 0
check "V3 unset: message names V_VERSION_3" "$(echo "$out" | grep -c 'V_VERSION_3 required')" 1
out=$(run_guard x ""); rc=$?
check "V3 empty: guard fails" "$([ "$rc" -ne 0 ] && echo fail)" fail
check "V3 empty: no side effect reached" "$(echo "$out" | grep -c SIDE_EFFECT)" 0
out=$(run_guard - y); rc=$?
check "V2 unset: guard fails, no side effect" "$([ "$rc" -ne 0 ] && [ "$(echo "$out" | grep -c SIDE_EFFECT)" -eq 0 ] && echo fail)" fail
out=$(run_guard x y); rc=$?
check "both present: guards pass" "$rc" 0
check "both present: side effect reached" "$(echo "$out" | grep -c SIDE_EFFECT)" 1
[ "$fails" -eq 0 ] && echo "PASS: c-rollback version guards" || exit 1
