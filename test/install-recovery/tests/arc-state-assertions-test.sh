#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
source "$ROOT/test/install-recovery/lib/arc-state-assertions.sh"

expect_pass() {
    "$@" || { echo "FAIL: expected pass: $*" >&2; exit 1; }
}

expect_reject() {
    if "$@"; then
        echo "FAIL: expected fail-closed rejection: $*" >&2
        exit 1
    fi
}

old_prefixed_prose_predicate() {
    local reason="${1:-}" target="${2:-}"
    [[ "$reason" == *"HEALTHCHECK_REST_DOWN: the application cannot serve at ${target} past warmup"* ]]
}

old_c9_db_stopped_predicate() {
    [ "${1:-}" != "running" ]
}

valid_reason="parked on deterministic forward failure: the application cannot serve at 0f4bce0d past warmup after 5 attempts"

# C9 current signature and fail-closed state controls.
expect_pass arc_c9_signature_is_nonterminal running in_progress t t
expect_reject arc_c9_signature_is_nonterminal stopped in_progress t t
expect_reject arc_c9_signature_is_nonterminal running completed t t
expect_reject arc_c9_signature_is_nonterminal running failed t t
expect_reject arc_c9_signature_is_nonterminal running in_progress f t
expect_reject arc_c9_signature_is_nonterminal running in_progress t ""

# Old-code negative proof: the stale predicate accepts the obsolete stopped-DB
# shape and rejects the intentional schema-floor-replay running-DB shape.
expect_pass old_c9_db_stopped_predicate stopped
expect_reject old_c9_db_stopped_predicate running

# Old-code negative proof: the valid structured representation has no enum prefix
# in prose, so the stale predicate rejects the actual current contract.
expect_reject old_prefixed_prose_predicate "$valid_reason" 0f4bce0d

# Split typed-code/prose contract and fail-closed code/state controls.
expect_pass arc_health_park_fields_match HEALTHCHECK_REST_DOWN "$valid_reason" 0f4bce0d
expect_reject arc_health_park_fields_match "" "$valid_reason" 0f4bce0d
expect_reject arc_health_park_fields_match MIGRATION_FAILED "$valid_reason" 0f4bce0d
expect_reject arc_health_park_fields_match HEALTHCHECK_REST_DOWN "parked on deterministic forward failure" 0f4bce0d
expect_reject arc_health_park_fields_match HEALTHCHECK_REST_DOWN "$valid_reason" deadbeef
expect_reject arc_health_park_fields_match HEALTHCHECK_REST_DOWN "$valid_reason" ""

echo "PASS: arc state assertions accept current signatures and fail closed on old/wrong/missing controls"
