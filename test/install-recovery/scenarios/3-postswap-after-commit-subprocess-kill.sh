#!/bin/bash
# HARNESS_SKIP_DEFAULT: requires arc env vars set by the upgrade-arc-harness.yaml
# construct job (BASE_SHA, B_FULL, B_BRANCH, V_VERSION, SB_ARC_TRUSTED_SIGNER).
# Excluded from the default harness run; invoke via the arc harness with
# scenario=after-commit-before-recorded-kill, or name this scenario explicitly:
#   ./dev.sh test-install-recovery 3-postswap-after-commit-subprocess-kill
#
# Scenario: 3-postswap-after-commit-subprocess-kill  (5d CAT-C Layer 0 — subprocess kill)
#
# Class:                 migrate-subprocess-killed-after-commit-before-recorded
# Class kind:            Stall (migrate.go:844)
# Recovery layer:        Layer 0 in-process (parent daemon, no prior systemd restart)
#
# Expected principled behavior:
#   The daemon's applyPostSwap spawns `./sb migrate up` as a subprocess.
#   The subprocess commits migration V's outer transaction (the fixture table
#   appears in the DB), then stalls in the ~ms window BEFORE the db.migration
#   INSERT. The harness SIGKILLs the subprocess — NOT the daemon parent.
#
#   The parent daemon catches the subprocess death: runCommandToLog returns
#   the kill-signal error → applyPostSwap → postSwapFailure → ground truth
#   check → GroundTruthBehind (V committed but unrecorded = HasPending=true
#   from the ledger's perspective) → rollback() → restoreDatabase (snapshot
#   restore, V's committed effects erased) → os.Exit(75). Systemd restarts
#   the daemon; the restarted daemon boots clean (no flag, no pending
#   migrations). Terminal: row=rolled_back.
#
#   This is Layer 0 in-process recovery: the SAME daemon process that ran
#   applyPostSwap handles the rollback. The subprocess kill does NOT require a
#   prior systemd restart — the parent orchestrates the full rollback pipeline
#   inline (one exit-75 restart total, vs two for the parent-kill arc).
#
# Trigger logic:
#   Delegates to test/install-recovery/arcs/after-commit-before-recorded-kill-arc.sh.
#   The arc requires env vars provided by the upgrade-arc-harness.yaml
#   construct job; see that workflow's scenario=after-commit-before-recorded-kill
#   input to run the full arc.
#
# Usage (arc harness):
#   In upgrade-arc-harness.yaml, set scenario=after-commit-before-recorded-kill.
#   The construct job creates the signed B branch with the non-idempotent
#   fixture migration; the run-arc job calls this arc with the env vars set.
#
# Usage (direct, requires manual env setup):
#   export BASE_SHA=<40-hex>
#   export B_FULL=<40-hex>
#   export B_BRANCH=test/arc-<runguid>/b
#   export V_VERSION=<timestamp>
#   export SB_ARC_TRUSTED_SIGNER=<pubkey>
#   HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-after-commit-subprocess-kill.sh \
#     statbus-recovery-3-postswap-after-commit-subprocess-kill

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-after-commit-subprocess-kill}"

# Validate required arc env vars before provisioning a VM.
: "${BASE_SHA:?BASE_SHA required — run via upgrade-arc-harness.yaml with scenario=after-commit-before-recorded-kill, or export manually}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"
: "${SB_ARC_TRUSTED_SIGNER:?SB_ARC_TRUSTED_SIGNER required}"

ARCS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/arcs"
arc="$ARCS_DIR/after-commit-before-recorded-kill-arc.sh"
[ -f "$arc" ] || { echo "✗ arc not found: $arc" >&2; exit 1; }
chmod +x "$arc"

exec "$arc" "$VM_NAME"
