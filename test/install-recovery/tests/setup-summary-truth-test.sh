#!/usr/bin/env bash
# STATBUS-502: the end-of-run summary must be TRUE. It may not print a success
# headline over a failed run, it may not describe work this run did not do
# (cloud-only stages, see STATBUS-501), and the general installation guidance may
# not push an operator onto a prerelease channel.
#
# STATBUS-376 D7: every summary line and next step is derived from the outcome
# each stage recorded in this run: ok, skipped, failed, or not applicable.
#
# Point STATBUS_SETUP_SCRIPT at an older copy to see this test fail, which makes
# the red half of the evidence.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${STATBUS_SETUP_SCRIPT:-$ROOT/ops/setup-ubuntu-lts.sh}"
fail=0

# Load the real summary printer and outcome registry.
REBOOT_DIR="$(mktemp -d)"
trap 'rm -rf "$REBOOT_DIR"' EXIT
export REBOOT_REQUIRED_FILE="$REBOOT_DIR/reboot-required"
export REBOOT_REQUIRED_PKGS_FILE="$REBOOT_DIR/reboot-required.pkgs"
source "$SCRIPT"
SERVICE_USER=statbus

line_of() { grep -nE "$1" "$SCRIPT" | head -1 | cut -d: -f1; }
present() { if [[ -n "$2" ]]; then echo "PASS $1"; else echo "FAIL $1 (not found)"; fail=1; fi; }
before() { if [[ -n "$2" && -n "$3" && "$2" -lt "$3" ]]; then echo "PASS $1"; else echo "FAIL $1 (${2:-missing} vs ${3:-missing})"; fail=1; fi; }

reset_summary() { # outcomes for stages 0..8, default all ok
    local n
    STAGE_OUTCOME=()
    for n in 0 1 2 3 4 5 6 7 8; do STAGE_OUTCOME[$n]=ok; done
    FAILED_VERIFICATIONS=()
    CLOUD=true
}
summary() { print_run_summary 2>&1; }
has() { grep -qF "$2" <<<"$1"; }
lacks() { ! grep -qF "$2" <<<"$1"; }

# 1. Failures must be reported BEFORE any success headline.
failures=$(line_of 'verification\(s\) failed across the run')
complete=$(line_of 'log_header "Setup Complete!"')
before "the failure list precedes the success headline" "$failures" "$complete"

# 2. A failure run must get its own headline, not "Complete".
present "a failed run has its own headline" "$(grep -n 'Setup finished WITH PROBLEMS' "$SCRIPT" | head -1)"

# 3. Every stage that ran is summarised; every next step names only work this
#    run actually did.
reset_summary
out="$(summary)"
for line in 'APT sources use HTTPS' \
            'Base system configured' \
            'SSH hardened (key-only authentication)' \
            'Automatic security updates enabled' \
            'CrowdSec intrusion detection and UFW firewall active' \
            'Docker and core tools installed' \
            'devops user created (ops/admin)' \
            'statbus service account created' \
            'CI command allowlist installed'; do
    has "$out" "$line" || { echo "FAIL all-ok summary is missing: $line"; fail=1; }
done
if has "$out" 'Next step: install StatBus as '"'"'statbus'"'"'.' \
    && has "$out" 'sudo -iu statbus' \
    && has "$out" 'the way you normally reach this server' \
    && has "$out" 'curl -fsSL https://statbus.org/install.sh | bash' \
    && has "$out" 'For later (optional):' \
    && has "$out" 'See what the intrusion detection has blocked:  cscli metrics' \
    && has "$out" 'Inspect the firewall rules:                    ufw status' \
    && ! grep -Eq '^[[:space:]]*[0-9]+\.[[:space:]]' <<<"$out" \
    && lacks "$out" '$(hostname' \
    && lacks "$out" 'ssh statbus@'; then
    echo "PASS all-ok summary has one install next step and an unnumbered optional reference"
else
    echo "FAIL all-ok summary does not match what ran"; echo "$out"; fail=1
fi

# 3b. A stage skipped by the operator appears as skipped, and its achievements
#     and next steps are absent.
reset_summary
STAGE_OUTCOME[4]=skipped
out="$(summary)"
if has "$out" 'Firewall and intrusion detection (Stage 4): skipped' \
    && lacks "$out" 'CrowdSec intrusion detection and UFW firewall active' \
    && lacks "$out" 'For later (optional):' \
    && lacks "$out" 'cscli metrics' \
    && lacks "$out" 'ufw status'; then
    echo "PASS a skipped Stage 4 appears as skipped and drops its next steps"
else
    echo "FAIL skipped Stage 4 summary is not derived from the recorded outcome"; echo "$out"; fail=1
fi

# 3c. A failed stage appears as failed, not configured.
reset_summary
STAGE_OUTCOME[5]=failed
FAILED_VERIFICATIONS=('Docker installed')
out="$(summary)"
if has "$out" 'Docker and core tools (Stage 5): failed' \
    && lacks "$out" 'Docker and core tools installed' \
    && has "$out" 'Setup finished WITH PROBLEMS'; then
    echo "PASS a failed Stage 5 appears as failed and is not claimed as configured"
else
    echo "FAIL failed Stage 5 summary is not derived from the recorded outcome"; echo "$out"; fail=1
fi

# 3d. Standalone: cloud-only stages are absent from the summary entirely, and a
#     skipped service-account stage drops the installer next step.
reset_summary
CLOUD=false
STAGE_OUTCOME[6]=na
STAGE_OUTCOME[8]=na
STAGE_OUTCOME[7]=skipped
out="$(summary)"
if lacks "$out" 'devops user' \
    && lacks "$out" 'CI command allowlist' \
    && has "$out" 'StatBus service account (Stage 7): skipped' \
    && lacks "$out" 'install.sh | bash'; then
    echo "PASS standalone summary omits cloud-only stages and skipped Stage 7 next steps"
else
    echo "FAIL standalone summary leaks or invents work"; echo "$out"; fail=1
fi

# 3e. A reboot flag that predates this run is Ubuntu's own pending update, not
#     work this setup did.
reset_summary
: > "$REBOOT_REQUIRED_FILE"
printf 'linux-image-6.8.0-40-generic\n' > "$REBOOT_REQUIRED_PKGS_FILE"
record_reboot_state
out="$(summary)"
if has "$out" 'Ubuntu reports a reboot is pending for updates installed before this run' \
    && has "$out" 'linux-image-6.8.0-40-generic' \
    && lacks "$out" 'to complete the setup' \
    && lacks "$out" 'This run installed updates'; then
    echo "PASS a pre-existing reboot flag is described as Ubuntu's earlier updates"
else
    echo "FAIL pre-existing reboot wording is wrong"; echo "$out"; fail=1
fi

# 3f. A flag that appeared during this run is this run's update.
rm -f "$REBOOT_REQUIRED_FILE" "$REBOOT_REQUIRED_PKGS_FILE"
record_reboot_state
: > "$REBOOT_REQUIRED_FILE"
out="$(summary)"
if has "$out" 'This run installed updates that need a reboot to take effect' \
    && lacks "$out" 'Ubuntu reports a reboot is pending' \
    && lacks "$out" 'to complete the setup'; then
    echo "PASS a newly appeared reboot flag is attributed to this run"
else
    echo "FAIL newly appeared reboot wording is wrong"; echo "$out"; fail=1
fi
rm -f "$REBOOT_REQUIRED_FILE" "$REBOOT_REQUIRED_PKGS_FILE"

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
