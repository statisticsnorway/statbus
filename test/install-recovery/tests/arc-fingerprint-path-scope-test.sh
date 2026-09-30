#!/usr/bin/env bash
# Offline regression test (STATBUS-425 M3b): capture_db_fingerprint's schema
# scratch file must be scoped per-VM_NAME, never a fixed path.
#
# Found live: EVERY arc that calls this function passes the SAME literal
# label ("baseline"). On Hetzner each arc gets its own throwaway VM (own
# filesystem), so a fixed tmp/arc-schema-baseline.sql path never collided.
# run-arcs.sh (STATBUS-425 M3b) runs many arcs CONCURRENTLY as sibling
# subshells sharing ONE host filesystem — two arcs racing on the same fixed
# path corrupted/truncated each other's file mid-write, and the loser's
# CENTERPIECE GUARD correctly refused with INCONCLUSIVE-INFRA (fail-loud,
# not a silent false pass) but lost a real verdict to pure filesystem
# contention, observed live across a real 35-arc run.
#
# Sources the REAL arc-helpers.sh (not a reimplementation) with real VM_EXEC/
# wait_for_worker_quiesce/HARNESS_ROOT stubs standing in for the guest, and
# runs capture_db_fingerprint under two DIFFERENT VM_NAME values with the
# SAME label ("baseline") — the exact shape two concurrent arcs produce —
# asserting the two calls write to genuinely different files.
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/statbus-fingerprint-scope.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

HARNESS_ROOT="$TMP/harness"
mkdir -p "$HARNESS_ROOT/tmp"

# Minimal real stubs for the guest-facing calls capture_db_fingerprint makes.
# Ledger/data calls must return a real-shaped sha256 (64 hex chars) since
# _assert_fingerprint_hash_usable validates the shape — VM_EXEC here stands
# in for the whole "psql | sha256sum" pipeline those helpers normally run
# guest-side, so it must hand back a value in that same shape. Each VM_NAME
# gets its own deterministic-but-distinct hash (sha256 of the name itself)
# so a same-path collision would be visible as wrong content, not just a
# missing file (a stronger assertion than existence alone).
VM_EXEC() {
    local cmd="$*"
    case "$cmd" in
        *"get POSTGRES_APP_DB"*) echo "db_${VM_NAME}" ;;
        *"get POSTGRES_ADMIN_USER"*) echo "user_${VM_NAME}" ;;
        *"pg_dump"*) printf -- "-- comment line\nCREATE TABLE t_%s (id int);\n" "$VM_NAME" ;;
        *"db.migration"*) printf '%s' "$VM_NAME-ledger" | sha256sum | cut -d' ' -f1 ;;
        *"legal_unit"*|*"establishment"*) printf '%s' "$VM_NAME-data" | sha256sum | cut -d' ' -f1 ;;
        *) echo "" ;;
    esac
}
wait_for_worker_quiesce() { return 0; }

# shellcheck source=../lib/assertions.sh
source "$ROOT/test/install-recovery/lib/assertions.sh"
# shellcheck source=../lib/arc-helpers.sh
source "$ROOT/test/install-recovery/lib/arc-helpers.sh"

VM_NAME=statbus-arc-fingerprint-scope-test-one
FP1=$(capture_db_fingerprint baseline)
[ -n "$FP1" ] || { echo "FAIL: first capture produced no fingerprint" >&2; exit 1; }

VM_NAME=statbus-arc-fingerprint-scope-test-two
FP2=$(capture_db_fingerprint baseline)
[ -n "$FP2" ] || { echo "FAIL: second capture produced no fingerprint" >&2; exit 1; }

# The two schema scratch files must be genuinely DIFFERENT paths (VM_NAME-scoped),
# both must exist, and each must contain that VM_NAME's own distinct content —
# not one overwriting or shadowing the other, which a fixed-name collision
# would produce (the second call's file would win, or a partial-write race
# would leave one empty).
F1="$HARNESS_ROOT/tmp/arc-schema-statbus-arc-fingerprint-scope-test-one-baseline.sql"
F2="$HARNESS_ROOT/tmp/arc-schema-statbus-arc-fingerprint-scope-test-two-baseline.sql"
[ -f "$F1" ] || { echo "FAIL: expected schema file for VM one not found: $F1" >&2; ls "$HARNESS_ROOT/tmp/" >&2; exit 1; }
[ -f "$F2" ] || { echo "FAIL: expected schema file for VM two not found: $F2" >&2; ls "$HARNESS_ROOT/tmp/" >&2; exit 1; }
grep -q "t_statbus-arc-fingerprint-scope-test-one" "$F1" || { echo "FAIL: VM one's schema file has wrong/missing content" >&2; cat "$F1" >&2; exit 1; }
grep -q "t_statbus-arc-fingerprint-scope-test-two" "$F2" || { echo "FAIL: VM two's schema file has wrong/missing content" >&2; cat "$F2" >&2; exit 1; }
[ "$FP1" != "$FP2" ] || { echo "FAIL: two different VMs' distinct content produced the SAME fingerprint — something is still shared" >&2; exit 1; }

echo "PASS: capture_db_fingerprint scopes its schema scratch file on VM_NAME — concurrent same-label calls from different arcs never collide"
