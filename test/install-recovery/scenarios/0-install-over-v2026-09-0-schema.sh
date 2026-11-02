#!/bin/bash
# Scenario: 0-install-over-v2026-09-0-schema
#
# A box genuinely installed at v2026.09.0 (schema ends at migration
# 20260901212308) is upgraded through the candidate's own install.sh with
# --version <candidate>. This is the STATBUS-559 incident shape: the program
# and checkout are swapped before ./sb install runs, and state detection must
# still resolve on the older schema. v2026.09.0 predates
# rollback_finish_pending_at (20260907120000), so the pre-migration probe must
# treat the missing column as "no rollback can be pending" instead of failing
# with SQLSTATE 42703 and stopping the install.
#
# Shape: fresh guest → the release's real sb-linux asset at v2026.09.0 through
# the candidate install.sh → assert the old schema → run the candidate
# install.sh --version <candidate> over it → assert the install completes, the
# binary and database schema are at the candidate, and the box serves.
#
# LXD checkpoint: LXD_BASELINE names the released baseline this scenario must
# start from; lxd_checkpoint_for_scenario forks installed-v2026.09.0-standalone,
# built once per candidate by the harness's historical-release path (a real
# v2026.09.0 sb plus its own ./sb install). The v2026.09.0 era predates
# STATBUS_ENV_CONFIG, so the current installer-input path cannot bootstrap it.
# LXD_BASELINE=v2026.09.0
#
# Usage:
#   ./test/install-recovery/scenarios/0-install-over-v2026-09-0-schema.sh <vm_name>
#
# Optional env:
#   KEEP_VM=1            Leave the VM running on failure for debugging
#   INSTALL_TARGET_TAG=... Release-shaped tag at HEAD (default: newest at HEAD)
#   INSTALL_BASE_VERSION=... Historical release to bootstrap (default v2026.09.0)

set -euo pipefail

VM_NAME="${1:-statbus-recovery-0-install-over-v2026-09-0-schema}"
HARNESS_DEPLOYMENT_MODE="${HARNESS_DEPLOYMENT_MODE:-standalone}"
HARNESS_UPGRADE_CHANNEL="${HARNESS_UPGRADE_CHANNEL:-stable}"
INSTALL_BASE_VERSION="${INSTALL_BASE_VERSION:-v2026.09.0}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"
source "$LIB_DIR/release-baseline.sh"

# The candidate is the release-shaped tag at HEAD, exactly as the smoke
# upgrade proves it; an untagged HEAD is not a candidate.
TARGET_TAGS=$(git -C "$REPO_ROOT" tag --points-at HEAD | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' || true)
if [ -z "${INSTALL_TARGET_TAG:-}" ]; then
    if [ -z "$TARGET_TAGS" ]; then
        echo "ERROR: 0-install-over-v2026-09-0-schema needs a release-shaped tag at HEAD; local runs may pass INSTALL_TARGET_TAG explicitly" >&2
        exit 1
    fi
    INSTALL_TARGET_TAG=$(printf '%s\n' "$TARGET_TAGS" | select_release_baseline_from_tags v9999.99.999999)
fi
_release_tag_parts "$INSTALL_TARGET_TAG" >/dev/null || {
    echo "ERROR: INSTALL_TARGET_TAG '$INSTALL_TARGET_TAG' is not a release-shaped stable/RC tag" >&2
    exit 1
}
_release_tag_parts "$INSTALL_BASE_VERSION" >/dev/null || {
    echo "ERROR: INSTALL_BASE_VERSION '$INSTALL_BASE_VERSION' is not a release-shaped stable/RC tag" >&2
    exit 1
}
TARGET_SHA=$(git -C "$REPO_ROOT" rev-parse "${INSTALL_TARGET_TAG}^{commit}")
if [ "$TARGET_SHA" != "$(git -C "$REPO_ROOT" rev-parse HEAD)" ]; then
    echo "ERROR: INSTALL_TARGET_TAG '$INSTALL_TARGET_TAG' does not point at HEAD" >&2
    exit 1
fi

# Derive each release's last migration from its own tree; never hard-code a
# version that a backport could silently invalidate.
last_migration() {
    git -C "$REPO_ROOT" ls-tree --name-only "$1" migrations/ \
        | sed -nE 's#^migrations/([0-9]{14})_.*\.up\.sql$#\1#p' \
        | sort | tail -1
}
BASE_LAST_MIGRATION=$(last_migration "$INSTALL_BASE_VERSION")
TARGET_LAST_MIGRATION=$(last_migration "$INSTALL_TARGET_TAG")
[ -n "$BASE_LAST_MIGRATION" ] || { echo "ERROR: no migrations found at $INSTALL_BASE_VERSION" >&2; exit 1; }
[ -n "$TARGET_LAST_MIGRATION" ] || { echo "ERROR: no migrations found at $INSTALL_TARGET_TAG" >&2; exit 1; }
if [ "$BASE_LAST_MIGRATION" = "$TARGET_LAST_MIGRATION" ]; then
    echo "ERROR: ${INSTALL_BASE_VERSION} and ${INSTALL_TARGET_TAG} end at the same migration ($BASE_LAST_MIGRATION); this scenario proves a schema delta" >&2
    exit 1
fi

source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 0-install-over-v2026-09-0-schema"
echo "  Base install: $INSTALL_BASE_VERSION (schema $BASE_LAST_MIGRATION)"
echo "  Candidate:    $INSTALL_TARGET_TAG ($TARGET_SHA, schema $TARGET_LAST_MIGRATION)"
echo "════════════════════════════════════════════════════════════════"

# 1. The harness baseline: a real v2026.09.0 install (its own released sb and
#    its own ./sb install on a pre-placed config, the STATBUS-369 legacy path).
#    Under LXD the fork already holds installed-v2026.09.0-standalone, so this
#    call confirms it; under the VM runner it performs the install.
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_BASE_VERSION"
echo ""
echo "── bootstrap: real $INSTALL_BASE_VERSION install ──"
install_statbus_in_vm "$VM_NAME" "$INSTALL_BASE_VERSION"

echo ""
echo "── assert the box really is $INSTALL_BASE_VERSION (schema without the pending marker) ──"
BASE_BINARY=$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version')
[[ "$BASE_BINARY" == *"$INSTALL_BASE_VERSION"* ]] || {
    echo "✗ bootstrap binary is '$BASE_BINARY', want $INSTALL_BASE_VERSION" >&2
    exit 1
}
BASE_DB_MIGRATION=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(MAX(version)::text, '') FROM db.migration;\" | ./sb psql -t -A" | tr -d ' \r\n')
[ "$BASE_DB_MIGRATION" = "$BASE_LAST_MIGRATION" ] || {
    echo "✗ bootstrap schema is $BASE_DB_MIGRATION, want $BASE_LAST_MIGRATION" >&2
    exit 1
}
PENDING_COLUMN=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='upgrade' AND column_name='rollback_finish_pending_at';\" | ./sb psql -t -A" | tr -d ' \r\n')
[ "$PENDING_COLUMN" = "0" ] || {
    echo "✗ bootstrap schema already has rollback_finish_pending_at ($PENDING_COLUMN); the regression shape is not present" >&2
    exit 1
}
echo "  ✓ $BASE_BINARY, schema $BASE_DB_MIGRATION, no rollback_finish_pending_at"

# 3. Install the candidate with install.sh --version over the old box. This is
#    the operator path from the incident: install.sh places the target program,
#    checks out the target, then ./sb install must detect state on the older
#    schema instead of failing with a missing column.
echo ""
echo "── install $INSTALL_TARGET_TAG over the $INSTALL_BASE_VERSION box ──"
UPGRADE_LOG=$(mktemp)
# VM_SCRIPT ships a local file and runs it as statbus with no inherited
# environment, so the disk floor the other harness installs pass is prepended
# to a copy of the candidate install.sh. Its own logic is otherwise unmodified.
INSTALL_SCRIPT_WITH_ENV=$(mktemp)
{
    printf '#!/bin/bash\nexport STATBUS_MIN_DISK_GB=5\n'
    cat "$REPO_ROOT/install.sh"
} > "$INSTALL_SCRIPT_WITH_ENV"
VM_SCRIPT "$INSTALL_SCRIPT_WITH_ENV" --version "$INSTALL_TARGET_TAG" --non-interactive --trust-github-user jhf >"$UPGRADE_LOG" 2>&1 || {
    rm -f "$INSTALL_SCRIPT_WITH_ENV"
    cat "$UPGRADE_LOG" >&2
    echo "✗ install.sh --version $INSTALL_TARGET_TAG failed over an $INSTALL_BASE_VERSION box" >&2
    exit 1
}
rm -f "$INSTALL_SCRIPT_WITH_ENV"
! grep -q 'could not be determined safely' "$UPGRADE_LOG" || {
    cat "$UPGRADE_LOG" >&2
    echo "✗ install.sh stopped in state detection over the older schema" >&2
    exit 1
}

# 4. The box now serves the candidate: binary identity, schema, health, and the
#    install's own ledger row.
echo ""
echo "── convergence checks ──"
BINARY_IDENTITY=$(VM_EXEC bash -c 'cd ~/statbus && ./sb --version')
EXPECTED_BINARY="sb version $INSTALL_TARGET_TAG (commit ${TARGET_SHA:0:8})"
[ "$BINARY_IDENTITY" = "$EXPECTED_BINARY" ] || {
    echo "✗ installed binary mismatch: expected='$EXPECTED_BINARY' actual='$BINARY_IDENTITY'" >&2
    exit 1
}
echo "  ✓ $BINARY_IDENTITY"

TARGET_DB_MIGRATION=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT COALESCE(MAX(version)::text, '') FROM db.migration;\" | ./sb psql -t -A" | tr -d ' \r\n')
[ "$TARGET_DB_MIGRATION" = "$TARGET_LAST_MIGRATION" ] || {
    echo "✗ schema is $TARGET_DB_MIGRATION after install, want $TARGET_LAST_MIGRATION" >&2
    exit 1
}
echo "  ✓ schema at $TARGET_DB_MIGRATION"

PENDING_COLUMN=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='upgrade' AND column_name='rollback_finish_pending_at';\" | ./sb psql -t -A" | tr -d ' \r\n')
[ "$PENDING_COLUMN" = "1" ] || {
    echo "✗ rollback_finish_pending_at is absent after install ($PENDING_COLUMN)" >&2
    exit 1
}

UPGRADE_IDENTITY=$(VM_EXEC bash -c "cd ~/statbus && ./sb psql -X -v ON_ERROR_STOP=1 -t -A -c \"SELECT commit_version, state FROM public.upgrade WHERE commit_sha = '$TARGET_SHA' ORDER BY id DESC LIMIT 1;\"")
EXPECTED_UPGRADE="$INSTALL_TARGET_TAG|completed"
[ "$UPGRADE_IDENTITY" = "$EXPECTED_UPGRADE" ] || {
    echo "✗ public.upgrade row for the candidate mismatch: expected='$EXPECTED_UPGRADE' actual='$UPGRADE_IDENTITY'" >&2
    exit 1
}
echo "  ✓ public.upgrade row for the candidate: $UPGRADE_IDENTITY"

assert_health_passes "$VM_NAME"
assert_harness_https_passes "$VM_NAME"

echo ""
echo "PASS: 0-install-over-v2026-09-0-schema (install.sh --version $INSTALL_TARGET_TAG completed over a real $INSTALL_BASE_VERSION database)"
