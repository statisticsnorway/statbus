#!/usr/bin/env bash
# STATBUS-391: exercise the real release-baseline → candidate upgrade service
# and its automatic post-upgrade fixup with the persisted 20/40 GB policy.
# 0-happy-upgrade owns candidate selection, VM lifetime, and health checks.
set -euo pipefail
export HARNESS_ASSERT_DISK_POLICY=1
exec "$(dirname "$0")/0-happy-upgrade.sh" "${1:-statbus-recovery-5-install-disk-threshold-repair}"
