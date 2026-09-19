#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/cloud.sh" "$TMP/cloud.sh"
mkdir -p "$TMP/bin"

cat >"$TMP/bin/ssh" <<'STUB'
#!/bin/bash
echo "stubbed ssh output"
STUB
chmod +x "$TMP/bin/ssh"

output=$(cd "$TMP" && PATH="$TMP/bin:$PATH" bash ./cloud.sh notify no 2>&1)
log_path=$(sed -n 's/^Logging to //p' <<<"$output" | head -1)

[ -n "$log_path" ] || { echo "FAIL: terminal output did not print the log path" >&2; exit 1; }
case "$log_path" in
    ./tmp/cloud-notify-no-*.log) ;;
    *) echo "FAIL: unexpected log path: $log_path" >&2; exit 1 ;;
esac
[ -f "$TMP/${log_path#./}" ] || { echo "FAIL: log file does not exist: $log_path" >&2; exit 1; }
grep -Fq "stubbed ssh output" "$TMP/${log_path#./}"
grep -Fq "Log saved to $log_path" <<<"$output"

set +e
failed_output=$(cd "$TMP" && bash -c 'STATBUS_CLOUD_LIB_ONLY=1 source ./cloud.sh; start_cloud_log notify no; echo "before failure"; false' 2>&1)
failed_rc=$?
set -e
[ "$failed_rc" -ne 0 ] || { echo "FAIL: failed operation unexpectedly succeeded" >&2; exit 1; }
failed_log_path=$(sed -n 's/^Logging to //p' <<<"$failed_output" | head -1)
[ -f "$TMP/${failed_log_path#./}" ] || { echo "FAIL: failed-command log does not exist" >&2; exit 1; }
grep -Fq "before failure" "$TMP/${failed_log_path#./}"
grep -Fq "The log has the full output: $failed_log_path" <<<"$failed_output"

echo "cloud logging tests: PASS"
