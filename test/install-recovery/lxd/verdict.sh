#!/usr/bin/env bash
# Only anchored scenario assertions count. The final assertion supersedes earlier ones.
lxd_scenario_verdict() {
    local log=$1 rc=$2 marker
    marker=$(awk '/^PASS:/ {last="PASS"} /^FAIL:/ {last="FAIL"} END {print last}' "$log")
    case "$marker:$rc" in
        PASS:0) printf 'PASS\n' ;;
        FAIL:*) printf 'FAIL\n' ;;
        :0) printf 'INVALID\n' ;;
        *) printf 'ERROR\n' ;;
    esac
}
