#!/usr/bin/env bash
# Offline end-to-end contract for the candidate-pinned LXD default selector.
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-lxd-selection.XXXXXX")
trap 'if [ "${KEEP_LXD_SELFTEST_TEMP:-0}" != 1 ]; then rm -rf "$TMP_ROOT"; else echo "SELFTEST_TEMP=$TMP_ROOT" >&2; fi' EXIT
REPO="$TMP_ROOT/repo"
mkdir -p "$REPO/test/install-recovery/"{lxd,lib,scenarios} "$TMP_ROOT/artifacts"
cp "$ROOT/test/install-recovery/lxd/"{run-forks,verdict,fleet-status}.sh "$REPO/test/install-recovery/lxd/"
cp "$ROOT/test/install-recovery/lxd/fleet-status.sh" "$REPO/test/install-recovery/lib/fleet-status.sh"
mkdir -p "$REPO/ops/lxd-fleet"
cp "$ROOT/ops/lxd-fleet/"{marker,admission}.sh "$REPO/ops/lxd-fleet/"
cat > "$REPO/test/install-recovery/lib/lxd-backend.sh" <<'EOF'
_lxd_prune_other_bases() { :; }
lxd_checkpoint_for_scenario() { echo stub-base; }
lxd_base_for_candidate() { :; }
_lxd_host() { return 1; }
EOF
cat > "$REPO/test/install-recovery/scenarios/skip.sh" <<'EOF'
#!/usr/bin/env bash
# HARNESS_SKIP_DEFAULT
EOF
cat > "$REPO/test/install-recovery/scenarios/0-happy-install.sh" <<'EOF'
#!/usr/bin/env bash
printf 'PASS: happy path excluded from LXD default\n'
EOF
chmod +x "$REPO/test/install-recovery/scenarios/"*.sh
git -C "$REPO" init -q
git -C "$REPO" config user.name 'Offline harness selftest'
git -C "$REPO" config user.email 'selftest@example.invalid'
git -C "$REPO" add .
git -C "$REPO" commit -qm 'empty default suite fixture'
git -C "$REPO" tag v2099.01.0-rc.1
git -C "$REPO" remote add origin "$REPO"
export JCODE_SCRATCH_DIR="$TMP_ROOT"
export LXD_FLEET_ARTIFACT_DIR="$TMP_ROOT/artifacts"
if bash "$REPO/test/install-recovery/lxd/run-forks.sh" v2099.01.0-rc.1 >"$TMP_ROOT/empty.log" 2>&1; then
    echo 'FAIL: empty default domain returned success' >&2
    exit 1
fi
grep -Fxq 'STATUS=FAILED' "$LXD_FLEET_ARTIFACT_DIR/fleet-status.txt" || { cat "$TMP_ROOT/empty.log" >&2; echo 'FAIL: empty domain did not write FAILED' >&2; exit 1; }
grep -q '^DETAIL=.*no default fault scenarios' "$LXD_FLEET_ARTIFACT_DIR/fleet-status.txt" || { cat "$LXD_FLEET_ARTIFACT_DIR/fleet-status.txt" >&2; exit 1; }
[ "$(wc -l < "$LXD_FLEET_ARTIFACT_DIR/comparison.tsv" | tr -d ' ')" = 2 ] || { echo 'FAIL: empty domain ran a fork' >&2; exit 1; }

cat > "$REPO/test/install-recovery/scenarios/1-fault.sh" <<'EOF'
#!/usr/bin/env bash
printf 'PASS: fault exercised\n'
EOF
git -C "$REPO" add .
git -C "$REPO" commit -qm 'populated default suite fixture'
git -C "$REPO" tag v2099.01.0-rc.2
bash "$REPO/test/install-recovery/lxd/run-forks.sh" v2099.01.0-rc.2 >"$TMP_ROOT/populated.log" 2>&1 || { cat "$TMP_ROOT/populated.log" >&2; exit 1; }
grep -Fxq 'STATUS=PASSED' "$LXD_FLEET_ARTIFACT_DIR/fleet-status.txt"
grep -q $'^1-fault\t\t\tPASS\t' "$LXD_FLEET_ARTIFACT_DIR/comparison.tsv"
[ "$(wc -l < "$LXD_FLEET_ARTIFACT_DIR/comparison.tsv" | tr -d ' ')" = 2 ] || { echo 'FAIL: default suite did not run exactly one fault' >&2; exit 1; }
echo 'PASS: empty candidate-pinned fault domain fails, populated default suite passes'
