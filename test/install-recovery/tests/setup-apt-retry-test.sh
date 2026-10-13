#!/usr/bin/env bash
# STATBUS-494: apt_retry must survive a transient apt failure by retrying with a
# refreshed package index, stop after a bounded number of attempts while naming
# the cause, and touch nothing when the first attempt works.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail (that copy
# has no apt_retry), which is how the red half of the evidence is produced.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0

helper="$(awk '/^apt_retry\(\)/,/^}/' "$SCRIPT")"
if [[ -z "$helper" ]]; then
    echo "FAIL apt_retry is not defined in $SCRIPT"
    exit 1
fi

sandbox="$(mktemp -d)"
export LOGDIR="$sandbox"
trap 'rm -rf "$sandbox"' EXIT

# A fake apt-get: counts install attempts, fails the first FAIL_TIMES of them
# exactly the way the Uganda run failed, and treats any update as success.
cat > "$sandbox/apt-get" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$LOGDIR/calls"
case "$*" in
    *update*) exit 0 ;;
esac
n=0
[[ -f "$LOGDIR/attempts" ]] && n="$(cat "$LOGDIR/attempts")"
n=$(( n + 1 ))
echo "$n" > "$LOGDIR/attempts"
if (( n <= ${FAIL_TIMES:-0} )); then
    echo "E: Failed to fetch http://archive.ubuntu.com/ubuntu/pool/main/g/git/git.deb  Hash Sum mismatch" >&2
    exit 100
fi
exit 0
FAKE
chmod +x "$sandbox/apt-get"
export PATH="$sandbox:$PATH"

log() { echo "[INFO] $*"; }
log_success() { echo "[OK] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*"; }
APT_RETRY_ATTEMPTS=3
APT_RETRY_DELAY_S=0
eval "$helper"

reset_case() { rm -f "$LOGDIR/attempts" "$LOGDIR/calls"; }
attempts() { cat "$LOGDIR/attempts" 2>/dev/null || echo 0; }
refreshes() { grep -c 'update' "$LOGDIR/calls" 2>/dev/null || true; }

# 1. A transient failure must be retried to success, with the index refreshed
#    between attempts.
reset_case; export FAIL_TIMES=2
out="$(apt_retry "test-transient" install -y pkg 2>&1)"; rc=$?
if [[ $rc -eq 0 && "$(attempts)" = "3" && "$(refreshes)" = "2" ]]; then
    echo "PASS transient failure retried to success (3 attempts, 2 index refreshes)"
else
    echo "FAIL transient case: rc=$rc attempts=$(attempts) refreshes=$(refreshes)"; fail=1
fi
grep -q 'succeeded on attempt 3' <<<"$out" || { echo "FAIL the success does not say which attempt won"; fail=1; }

# 2. A persistent failure must stop at the bound and name the cause.
reset_case; export FAIL_TIMES=99
out="$(apt_retry "test-persistent" install -y pkg 2>&1)"; rc=$?
if [[ $rc -ne 0 && "$(attempts)" = "3" ]]; then
    echo "PASS persistent failure stopped after 3 attempts"
else
    echo "FAIL persistent case: rc=$rc attempts=$(attempts)"; fail=1
fi
grep -qi 'intermediary' <<<"$out" || { echo "FAIL the give-up message does not name the cause"; fail=1; }

# 3. A working first attempt must not be retried and must not refresh anything.
reset_case; export FAIL_TIMES=0
out="$(apt_retry "test-first" install -y pkg 2>&1)"; rc=$?
if [[ $rc -eq 0 && "$(attempts)" = "1" && "$(refreshes)" = "0" ]]; then
    echo "PASS a working first attempt is not retried"
else
    echo "FAIL first-attempt case: rc=$rc attempts=$(attempts) refreshes=$(refreshes)"; fail=1
fi

exit $fail
