#!/usr/bin/env bash
# STATBUS-502: the end-of-run summary must be TRUE. It may not print a success
# headline over a failed run, it may not describe work this run did not do
# (cloud-only stages, see STATBUS-501), and the general installation guidance may
# not push an operator onto a prerelease channel.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail, which makes
# the red half of the evidence.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0

line_of() { grep -nE "$1" "$SCRIPT" | head -1 | cut -d: -f1; }
present() { if [[ -n "$2" ]]; then echo "PASS $1"; else echo "FAIL $1 (not found)"; fail=1; fi; }
before() { if [[ -n "$2" && -n "$3" && "$2" -lt "$3" ]]; then echo "PASS $1"; else echo "FAIL $1 (${2:-missing} vs ${3:-missing})"; fail=1; fi; }

# 1. Failures must be reported BEFORE any success headline.
failures=$(line_of 'verification\(s\) failed across the run')
complete=$(line_of 'log_header "Setup Complete!"')
before "the failure list precedes the success headline" "$failures" "$complete"

# 2. A failure run must get its own headline, not "Complete".
present "a failed run has its own headline" "$(grep -n 'Setup finished WITH PROBLEMS' "$SCRIPT" | head -1)"

# 3. Cloud-only achievements are described only when this run did them.
for entry in 'echo "  - devops user created (ops/admin)"' 'echo "  - CI command allowlist installed from the repo'; do
    antecedent="$(grep -B1 -F "$entry" "$SCRIPT" | head -1)"
    if grep -q 'CLOUD:-false' <<<"$antecedent"; then
        echo "PASS cloud-gated summary entry: ${entry:0:40}"
    else
        echo "FAIL summary entry is not cloud-gated: ${entry:0:40}"; fail=1
    fi
done

# 4. The general installation guidance names NO channel at all: stable is the
#    default, and naming our internal channels would invite an ordinary operator
#    to pick one (the same leak STATBUS-501 removed from the stages).
install_line="$(grep -n 'install.sh | bash' "$SCRIPT" | head -1)"
if [[ -n "$install_line" ]] && ! grep -q -- '--channel' <<<"$install_line"; then
    echo "PASS the general install guidance names no channel"
else
    echo "FAIL the general install guidance names a channel: ${install_line:-missing}"; fail=1
fi

# 5. A failed run must still exit non-zero.
present "a failed run still exits non-zero" "$(grep -n 'exit 1' "$SCRIPT" | tail -1)"

exit $fail
