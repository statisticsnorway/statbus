#!/usr/bin/env bash
# Offline producer/consumer identity test (review N1): run-smoke.sh's
# 0-happy-upgrade leg computes a checkpoint name and later the fork spawned
# by bootstrap_install_test_vm -> lxd_fork resolves ITS OWN idea of that same
# checkpoint name in a genuinely separate `bash` child process (exactly the
# shape run-smoke.sh uses: `bash .../scenarios/$SCENARIO.sh`). A prior
# version of run-smoke.sh re-spelled the name by hand instead of calling
# lxd_checkpoint_for_scenario, and the two diverged the moment the "-pre"
# suffix was introduced: the producer wrote "...-pre", the fork's own
# lxd_checkpoint_for_scenario (unaware of the suffix) still resolved the
# unsuffixed name, so 0-happy-upgrade's fork went looking for a checkpoint
# that was never built under that name.
#
# This exercises the REAL lxd_checkpoint_for_scenario, not a paraphrase, via
# a minimal fixture repo (the same technique lxd-default-domain-test.sh
# uses) so the assertion does not depend on the main repo's tag history.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/lxd-checkpoint-identity.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/test/install-recovery/lib" "$REPO/test/install-recovery/scenarios"
cp "$ROOT/test/install-recovery/lib/lxd-backend.sh" "$REPO/test/install-recovery/lib/"
cp "$ROOT/test/install-recovery/lib/release-baseline.sh" "$REPO/test/install-recovery/lib/"

# Fixture scenario matching the real 0-happy-upgrade.sh's baseline-selector
# shape (lxd_checkpoint_for_scenario resolves on FILE CONTENT, never
# execution, so a comment mentioning the selector is sufficient and faithful
# to how the real function inspects real scenario files).
cat > "$REPO/test/install-recovery/scenarios/0-happy-upgrade.sh" <<'EOF'
#!/usr/bin/env bash
# fixture: select_release_baseline_from_repo
EOF
# Fixture fault-fleet delegator, matching the real
# 5-install-disk-threshold-repair.sh's exact `exec ".../0-happy-upgrade.sh"`
# shape so lxd_checkpoint_for_scenario's delegation regex actually fires and
# recurses into the fixture above, exactly as it does for the real scenario.
cat > "$REPO/test/install-recovery/scenarios/5-install-disk-threshold-repair.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/0-happy-upgrade.sh" "${1:-statbus-recovery-5-install-disk-threshold-repair}"
EOF
chmod +x "$REPO/test/install-recovery/scenarios/"*.sh

git -C "$REPO" init -q
git -C "$REPO" config user.name 'Offline harness selftest'
git -C "$REPO" config user.email 'selftest@example.invalid'
git -C "$REPO" add .
git -C "$REPO" commit -qm 'baseline fixture'
git -C "$REPO" tag v2099.01.0
git -C "$REPO" commit -qm 'candidate fixture' --allow-empty
git -C "$REPO" tag v2099.01.1-rc.1

# shellcheck disable=SC1091
source "$REPO/test/install-recovery/lib/lxd-backend.sh"
export LXD_CANDIDATE=v2099.01.1-rc.1

# --- run-smoke.sh's own producer path (test/install-recovery/lxd/run-smoke.sh) ---
export HARNESS_UPGRADE_CHANNEL=prerelease
export LXD_BASELINE_CHECKPOINT_SUFFIX=-pre
producer=$(lxd_checkpoint_for_scenario 0-happy-upgrade)
[ "$producer" = "installed-v2099.01.0-standalone-pre" ] || {
    echo "FAIL: producer checkpoint = $producer (expected installed-v2099.01.0-standalone-pre)" >&2
    exit 1
}

# --- the fork's own resolution, in a genuinely separate bash process (the
# shape run-smoke.sh actually uses: `bash .../scenarios/$SCENARIO.sh`, which
# re-sources lxd-backend.sh fresh). LXD_BASELINE_CHECKPOINT_SUFFIX crosses the
# process boundary only because run-smoke.sh EXPORTS it, not merely sets it.
consumer=$(bash -c '
set -euo pipefail
source "'"$REPO"'/test/install-recovery/lib/lxd-backend.sh"
lxd_checkpoint_for_scenario 0-happy-upgrade
')
[ "$consumer" = "$producer" ] || {
    echo "FAIL: producer=$producer consumer=$consumer diverge (review N1 regression)" >&2
    exit 1
}
echo "PASS: run-smoke's checkpoint and its own fork's resolution agree ($producer)"

# --- run-forks.sh's env: LXD_BASELINE_CHECKPOINT_SUFFIX is never set. A
# baseline fault-fleet scenario that delegates to 0-happy-upgrade.sh (which
# itself defaults HARNESS_UPGRADE_CHANNEL to prerelease) must still resolve
# the UNSUFFIXED name the fault fleet's own fallback builder
# (_lxd_build_base_for_candidate, called with no suffix) actually builds. ---
unset LXD_BASELINE_CHECKPOINT_SUFFIX
export HARNESS_UPGRADE_CHANNEL=prerelease
fault=$(lxd_checkpoint_for_scenario 5-install-disk-threshold-repair)
[ "$fault" = "installed-v2099.01.0-standalone" ] || {
    echo "FAIL: fault-fleet checkpoint = $fault (expected unsuffixed installed-v2099.01.0-standalone)" >&2
    exit 1
}
unset HARNESS_UPGRADE_CHANNEL
fault_stable=$(lxd_checkpoint_for_scenario 5-install-disk-threshold-repair)
[ "$fault_stable" = "installed-v2099.01.0-standalone" ] || {
    echo "FAIL: fault-fleet checkpoint (harness-default stable channel) = $fault_stable" >&2
    exit 1
}
echo "PASS: fault-fleet baseline scenarios resolve the unsuffixed checkpoint regardless of channel"

# Resolve the real shared body and wrappers, not a paraphrased selector.
cp "$ROOT/test/install-recovery/scenarios/5-install-source-image-identity-proof.sh" "$REPO/test/install-recovery/scenarios/"
cp "$ROOT/test/install-recovery/scenarios/5-install-source-identity-"{operator,scheduled}.sh "$REPO/test/install-recovery/scenarios/"
for slug in 5-install-source-image-identity-proof 5-install-source-identity-operator 5-install-source-identity-scheduled; do
    checkpoint=$(lxd_checkpoint_for_scenario "$slug")
    [ "$checkpoint" = hardened-nothing-installed ]
    printf 'PASS: %s resolves to %s\n' "$slug" "$checkpoint"
done

# Capture, never execute, the real historical helper's remote install body.
# Unstubbed transports refuse every external operation.
_lxd_upload() {
    case "$2" in
        /root/s2-env-config-*) cp "$1" "$TMP/fresh-config" ;;
        /root/s2-users-*.yml) : ;;
        *) return 97 ;;
    esac
}
_lxd_push() { :; }
VM_EXEC() { [ "$*" = 'test ! -e /home/statbus/statbus' ] || return 97; }
VM_SCRIPT_INLINE() { printf '%s\n' "$*" > "$TMP/helper-args"; cat > "$TMP/helper-body"; }
_lxd_stage_candidate_install() { :; }
_lxd_mark() { printf '%s\n' "$*"; }
export HARNESS_DEPLOYMENT_MODE=private HARNESS_UPGRADE_CHANNEL=prerelease
VM_NAME=statbus-recovery-source-proof
export LXD_LOG_DIR="$TMP"
_lxd_host() {
    case "$*" in
        'rm -f '*|'lxc exec '*'/tmp/env-config'|'lxc exec '*'/tmp/users.yml') return 0 ;;
        *) echo "REFUSE unexpected host operation: $*" >&2; return 97 ;;
    esac
}
unset GITHUB_TOKEN
_lxd_prepare_fresh_answers
grep -Fxq 'CADDY_DEPLOYMENT_MODE=private' "$TMP/fresh-config"
grep -Fxq 'UPGRADE_CHANNEL=prerelease' "$TMP/fresh-config"
old_sha=$(git -C "$REPO" rev-parse v2099.01.0)
install_statbus_at_sha "$VM_NAME" "$old_sha"
grep -Fxq 'arc-historical-install v2099.01.0 private 0' "$TMP/helper-args"
grep -Fq 'releases/download/v2099.01.0/sb-linux-amd64' "$TMP/helper-body"
grep -Fq 'git clone --quiet --depth 50 --branch v2099.01.0' "$TMP/helper-body"
grep -Fq 'cp /tmp/env-config .env.config' "$TMP/helper-body"
grep -Fq './sb install --non-interactive --trust-github-user jhf' "$TMP/helper-body"
echo 'PASS: actual historical helper chooses released binary/checkout with fresh private/prerelease answers (captured, not executed)'
