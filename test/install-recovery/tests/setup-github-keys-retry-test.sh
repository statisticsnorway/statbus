#!/usr/bin/env bash
# Setup installs the login keys of the GitHub users in GITHUB_USERS
# (populate_authorized_keys). GitHub answering nothing for a moment must not
# leave the account without a key: the fetch is retried, and when GitHub stays
# unreachable setup says so and records the failure. A user who simply has no
# ED25519 key is told that, without retrying.
#
# Observed: rc.12 gate (Test Smoke 42043619999, 2026-11-05, GitHub degraded):
# one fetch of https://github.com/jhf.keys answered nothing, setup carried on
# with 0 keys, and only the later verifications failed.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail, which is
# how the red half of the evidence is produced.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0

functions=""
for name in fetch_github_keys count_authorized_key_bodies populate_authorized_keys; do
    functions+="$(awk "/^${name}\\(\\)/,/^}/" "$SCRIPT")"$'\n'
done
grep -q '^populate_authorized_keys()' <<<"$functions" || { echo "FAIL populate_authorized_keys is not defined in $SCRIPT"; exit 1; }

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export LOGDIR="$sandbox"
mkdir -p "$sandbox/home" "$sandbox/bin"

# A curl that behaves like the real one under `-sS -L --fail`: the first
# FAIL_TIMES calls time out (exit 28, message on stderr, nothing on stdout),
# later calls print the body GitHub serves for the URL (its last argument).
cat > "$sandbox/bin/curl" <<'FAKE'
#!/usr/bin/env bash
n=0
[[ -f "$LOGDIR/attempts" ]] && n="$(cat "$LOGDIR/attempts")"
n=$(( n + 1 ))
echo "$n" > "$LOGDIR/attempts"
if (( n <= ${FAIL_TIMES:-0} )); then
    echo "curl: (28) Operation timed out after 10001 milliseconds with 0 bytes received" >&2
    exit 28
fi
printf '%s' "${KEYS_BODY:-}"
exit 0
FAKE
chmod +x "$sandbox/bin/curl"
export PATH="$sandbox/bin:$PATH"

# The account lookups and ownership changes need root on a real box; here the
# account is the sandbox home.
getent() { echo "statbus:x:1000:1000::$sandbox/home:/bin/bash"; }
chown() { :; }
log() { echo "[INFO] $*"; }
log_success() { echo "[OK] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*"; }
verify() {
    if eval "$2" &>/dev/null; then return 0; fi
    FAILED_VERIFICATIONS+=("$1")
    return 1
}
GITHUB_KEYS_FETCH_ATTEMPTS=4
GITHUB_KEYS_FETCH_DELAY_S=0
eval "$functions"

KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
reset_case() {
    rm -f "$LOGDIR/attempts" "$sandbox/home/.ssh/authorized_keys"
    FAILED_VERIFICATIONS=()
}
attempts() { cat "$LOGDIR/attempts" 2>/dev/null || echo 0; }
installed_keys() { grep -c '^ssh-ed25519 ' "$sandbox/home/.ssh/authorized_keys" 2>/dev/null || echo 0; }

# 1. GitHub answers nothing twice, then serves the key: the key is installed.
reset_case; export FAIL_TIMES=2 KEYS_BODY="$KEY"$'\n'
out="$(populate_authorized_keys statbus "jhf" "" 2>&1; echo "rc=$?")"
if [[ "$(installed_keys)" = 1 && "$(attempts)" = 3 && "$out" == *"rc=0"* ]]; then
    echo "PASS a brief GitHub outage is retried and the key is installed"
else
    echo "FAIL brief outage: keys=$(installed_keys) attempts=$(attempts)"; echo "$out"; fail=1
fi

# 2. GitHub stays unreachable: bounded attempts, the cause is named, and the
#    failure is recorded so setup ends WITH PROBLEMS.
reset_case; export FAIL_TIMES=99 KEYS_BODY="$KEY"$'\n'
out="$(populate_authorized_keys statbus "jhf" "" 2>&1; echo "rc=$?")"
if [[ "$(attempts)" = 4 && "$out" != *"rc=0"* ]]; then
    echo "PASS an unreachable GitHub stops after 4 attempts and fails"
else
    echo "FAIL persistent outage: attempts=$(attempts)"; echo "$out"; fail=1
fi
grep -q 'Could not reach GitHub for the SSH keys of jhf' <<<"$out" || { echo "FAIL the failure does not say GitHub could not be reached for jhf's keys"; echo "$out"; fail=1; }
# The recorded failure is checked in the same shell as the call.
reset_case; populate_authorized_keys statbus "jhf" "" >/dev/null 2>&1
if [[ "${FAILED_VERIFICATIONS[*]:-}" == *"SSH keys of jhf fetched from GitHub"* ]]; then
    echo "PASS the unreachable GitHub is recorded as a failed verification"
else
    echo "FAIL not recorded: FAILED_VERIFICATIONS=(${FAILED_VERIFICATIONS[*]:-})"; fail=1
fi

# 3. GitHub answers, but the user has no ED25519 key: one attempt, told so.
reset_case; export FAIL_TIMES=0 KEYS_BODY=$'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ\n'
out="$(populate_authorized_keys statbus "jhf" "" 2>&1; echo "rc=$?")"
if [[ "$(attempts)" = 1 ]] && grep -q 'GitHub user jhf has no ED25519 key' <<<"$out"; then
    echo "PASS a user without an ED25519 key is told so without retrying"
else
    echo "FAIL no-key case: attempts=$(attempts)"; echo "$out"; fail=1
fi

exit $fail
