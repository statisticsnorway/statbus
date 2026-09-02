#!/bin/bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/../lib/watch-decisions.sh"

assert_eq() {
    local want="$1" got="$2" name="$3"
    if [ "$got" != "$want" ]; then
        echo "FAIL: $name: want '$want', got '$got'" >&2
        exit 1
    fi
    echo "PASS: $name -> $got"
}

assert_eq success "$(watch_ssh_rc_class 0)" "successful SSH probe"
assert_eq reconnect "$(watch_ssh_rc_class 255)" "SSH rc=255 reconnects"
assert_eq reconnect "$(watch_ssh_rc_class 124)" "bounded probe timeout reconnects"
assert_eq fatal "$(watch_ssh_rc_class 1)" "remote command failure is not a reconnect"

assert_eq retry "$(watch_reconnect_decision 255 2 5 alive)" "rc=255 retries inside the window"
assert_eq resume "$(watch_reconnect_decision 255 5 5 alive)" "live VM resumes after bounded window"
assert_eq resume "$(watch_reconnect_decision 255 5 5 unknown)" "provider uncertainty does not claim VM death"
assert_eq vm-gone "$(watch_reconnect_decision 255 5 5 missing)" "provider-confirmed missing VM fails"

assert_eq advanced "$(watch_progress_decision 11 10 200 100 300)" "new lines are progress"
assert_eq waiting "$(watch_progress_decision 10 10 399 100 300)" "silence inside window waits"
assert_eq stalled "$(watch_progress_decision 10 10 400 100 300)" "silence at window is stalled"

echo "watch decision tests: PASS"
