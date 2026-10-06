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

# Use the real delegators and real driver, replacing only the expensive shared
# guest body in this fixture. The body observes the path/tag/process boundary.
cp "$ROOT/test/install-recovery/scenarios/5-install-source-identity-"{operator,scheduled}.sh "$REPO/test/install-recovery/scenarios/"
cat > "$REPO/test/install-recovery/scenarios/5-install-source-image-identity-proof.sh" <<'EOF'
#!/usr/bin/env bash
# HARNESS_SKIP_DEFAULT
set -euo pipefail
[ "$INSTALL_TARGET_TAG" = "$LXD_CANDIDATE" ]
printf 'cell=%s vm=%s tag=%s\n' "$CANDIDATE_PATH" "$1" "$INSTALL_TARGET_TAG"
if [ "${MISSING_PATH:-}" = "$CANDIDATE_PATH" ]; then
    # Real subprocess loss before the driver's row write, not a substitute
    # aggregation algorithm or a fabricated comparison file.
    kill -KILL "$PPID"
    exit 1
fi
if [ "${FAIL_PATH:-}" = "$CANDIDATE_PATH" ]; then echo 'FAIL: route failed'; exit 1; fi
echo "PASS: $CANDIDATE_PATH route"
EOF
chmod +x "$REPO/test/install-recovery/scenarios/"*.sh
run_cells() {
    local number=$1 expected=$2 rc=0 path slug
    git -C "$REPO" add .
    git -C "$REPO" commit -qm "two-cell fixture $number" --allow-empty
    git -C "$REPO" tag "v2099.01.0-rc.$number"
    bash "$REPO/test/install-recovery/lxd/run-forks.sh" "v2099.01.0-rc.$number" >"$TMP_ROOT/cells-$number.log" 2>&1 || rc=$?
    grep -Fxq "STATUS=$expected" "$LXD_FLEET_ARTIFACT_DIR/fleet-status.txt" || { cat "$TMP_ROOT/cells-$number.log" >&2; exit 1; }
    if [ "$expected" = PASSED ]; then [ "$rc" = 0 ]; else [ "$rc" != 0 ]; fi
    for path in operator scheduled; do
        slug=5-install-source-identity-$path
        grep -Fq "cell=$path vm=statbus-recovery-$slug tag=v2099.01.0-rc.$number" "$LXD_FLEET_ARTIFACT_DIR/$slug.log"
        if [ "${MISSING_PATH:-}" != "$path" ]; then
            grep -q "^$slug"$'\t' "$LXD_FLEET_ARTIFACT_DIR/comparison.tsv"
        fi
        printf 'cell log %s: ' "$slug"; cat "$LXD_FLEET_ARTIFACT_DIR/$slug.log"
    done
    cat "$LXD_FLEET_ARTIFACT_DIR/comparison.tsv"
    printf 'driver case %s: exit=%s status=%s\n' "$number" "$rc" "$expected"
}
run_cells 3 PASSED
[ "$(wc -l < "$LXD_FLEET_ARTIFACT_DIR/comparison.tsv" | tr -d ' ')" = 4 ]
export FAIL_PATH=operator
run_cells 4 FAILED
export FAIL_PATH=scheduled
run_cells 5 FAILED
unset FAIL_PATH
export MISSING_PATH=operator
run_cells 6 FAILED
grep -Fq 'Missing result: 5-install-source-identity-operator' "$TMP_ROOT/cells-6.log"
unset MISSING_PATH
echo 'PASS: two default cells have distinct logs/rows; either route failure and missing result refuse aggregate PASS'
