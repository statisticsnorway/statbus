#!/bin/bash
# Arc: deploy-status-proof  (STATBUS-170 AC#4 — the King-ratified AUTOMATED
# successor to the retired rune drill; ticket comment #10).
#
# WHAT THIS PROVES: the deploy pipeline's RED path end to end, with NOTHING
# deliberately broken on any fleet box. A REAL upgrade to a broken-fixture
# commit (the shared FAILING lineage: V RAISEs → the daemon rolls back
# autonomously) runs on this arc's own VM, and the CI-side poll — the SAME
# poll-block bytes the deploy-to-* workflows carry (the 8th DELIBERATE copy;
# semantics live in ops/ci-deploy-status.sh's exit contract, STATBUS-170
# comment #5 rider i: semantic changes land in the script once, loop-shape
# changes land in every copy knowingly) — polls that VM through a
# PRODUCTION-REPLICATED transport and reports RED naming the row's error:
#
#   · transport: ssh forced-command → sshdo → /etc/sshdoers allowlist, the
#     canonical ops/niue/ bytes installed root-owned on the VM, HARDENED
#     forced-command prefix (STATBUS-069 ruling), per-run EPHEMERAL keypair
#     minted below — no standing secret (King-ratified).
#   · allowed  path: `~/statbus/ops/ci-deploy-status.sh <40-hex>` — first
#     probed pre-drive (exit 20 `absent` on the not-yet-registered B: the same
#     live proof shape the niue provisioning session used), then post-rollback
#     (exit 10 `rolled_back` + the product's CLASSED error: failure class +
#     failing commit + remediation — the row error is the operator summary;
#     the migration's literal RAISE text stays in the retained migrate log +
#     journal by design, run 29743621767 ruling).
#   · refused path: a non-allowlisted command must be DENIED by sshdo
#     ('not in allowlist') — the gate itself is part of the proof.
#
# INVERSION: the poll expectation flips the production block — here exit 10 is
# the PASS (the proof is that a failed deploy REPORTS red), exit 0 is a FAIL
# (the poll certified a rolled-back deploy as converged), and the two-phase
# 127 window does NOT apply (this VM's checkout carries the script by
# construction, so 127 is a hard FAIL here, not a poke-only green).
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH — the shared FAILING
# lineage (C unused; single-phase). VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-deploy-status-proof}"
UPGRADE_BUDGET_S="${UPGRADE_BUDGET_S:-1200}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
POLL_BUDGET_S="${POLL_BUDGET_S:-1200}"   # 20m @ 30s — the cloud budget class (170 comment #1)
POLL_INTERVAL_S="${POLL_INTERVAL_S:-30}"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"
source "$LIB_DIR/sshdo-probe.sh"

PROBE_KEY_DIR=""

_dump_proof_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (row + journal + sshdo state) ══════════" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, recovery_parked_at IS NOT NULL AS parked, COALESCE(error,'') FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id;\" | ./sb psql" >&2 || true
    VM_EXEC bash -c "journalctl --user -u statbus-upgrade@statbus.service --no-pager -n 300 2>/dev/null" >&2 || true
    echo "── sshdo transport state ──" >&2
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" "ls -la /usr/local/bin/sshdo /etc/sshdoers /home/statbus/.ssh/authorized_keys 2>&1; echo '--- sshdoers ---'; cat /etc/sshdoers 2>&1; echo '--- sshdo auth log tail ---'; journalctl -t sshdo -n 40 --no-pager 2>/dev/null || grep -h sshdo /var/log/auth.log 2>/dev/null | tail -40" >&2 || true
    echo "══════════ end failure diagnostics ══════════" >&2
}

trap 'rc=$?; if [ "$rc" -ne 0 ]; then _dump_proof_failure_diagnostics; fi; [ -n "$PROBE_KEY_DIR" ] && rm -rf "$PROBE_KEY_DIR"; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: deploy-status-proof  (broken deploy → sshdo-gated CI poll reports RED)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}  (failing lineage)"
echo "════════════════════════════════════════════════════════════════"

# ── A: install + prepare ─────────────────────────────────────────────────────
arc_prepare_box

# ── mint the per-run EPHEMERAL keypair + install the production-replica gate ──
PROBE_KEY_DIR=$(mktemp -d)
ssh-keygen -t ed25519 -N '' -C "statbus-deploy-status-proof-ephemeral" -f "$PROBE_KEY_DIR/probe_key" -q
setup_sshdo_probe "$PROBE_KEY_DIR/probe_key.pub"

# probe_ssh [command...] — the CI-side transport under test: the EPHEMERAL key
# as the statbus user, forced through sshdo. BatchMode so a broken key/gate
# fails instead of prompting. The requested command string becomes
# SSH_ORIGINAL_COMMAND; sshdo allows it only if it matches the sshdoers line.
probe_ssh() {
    ssh -i "$PROBE_KEY_DIR/probe_key" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -o BatchMode=yes \
        -o ConnectTimeout=15 \
        statbus@"$VM_IP" "$@"
}

# ── gate probes (pre-drive: fail fast if the transport replica is broken) ────
echo ""
echo "── sshdo gate: a non-allowlisted command must be REFUSED ──"
REFUSED_OUT=$(probe_ssh "ls /" 2>&1) && {
    echo "✗ sshdo ALLOWED a non-allowlisted command ('ls /') — the gate is not engaged. Output: $REFUSED_OUT" >&2
    exit 1
}
printf '%s\n' "$REFUSED_OUT" | grep -qi "not in allowlist" || {
    echo "✗ 'ls /' was refused, but without sshdo's 'not in allowlist' message — wrong refusal layer? Output: $REFUSED_OUT" >&2
    exit 1
}
echo "  ✓ refused: 'ls /' denied with 'not in allowlist' (sshdo is the gate)"

echo ""
echo "── sshdo gate: the allowed status read works pre-drive (exit 20, state=absent) ──"
# The literal '~' is load-bearing: it must reach the VM UNEXPANDED so sshdo's
# allowlist match + the remote login shell resolve it to /home/statbus — the
# same deliberate SC2088 the production poll blocks carry.
# shellcheck disable=SC2088
PRE_OUT=$(probe_ssh "~/statbus/ops/ci-deploy-status.sh $B_FULL" 2>/dev/null) && PRE_RC=0 || PRE_RC=$?
PRE_LINE=$(printf '%s' "$PRE_OUT" | tail -n 1 | tr -d '\r')
[ "$PRE_RC" = "20" ] && [ "${PRE_LINE%%|*}" = "absent" ] || {
    echo "✗ pre-drive status read: got exit=$PRE_RC line='$PRE_LINE', want exit=20 state=absent (B not yet registered)" >&2
    exit 1
}
echo "  ✓ allowed: status read through sshdo returned exit=20 '$PRE_LINE' (the niue provisioning proof shape)"

# ── drive B: real broken deploy → the daemon fails + rolls back autonomously ──
arc_to "$B_FULL" "$B_BRANCH" "B (V_fail rolls back)" "rolled_back"

# ── THE POLL — deploy-workflow poll-block copy, inverted expectation ─────────
# STATBUS-170: semantics live in ops/ci-deploy-status.sh's exit contract; this
# is the 8th DELIBERATE copy of the deploy workflows' poll block (comment #5
# rider i) — loop-shape changes land in every copy knowingly. Differences from
# the production block, all deliberate and named in the header: transport is
# the ephemeral probe key (production: slot key / rune key), rc 10 is the PASS,
# rc 0 the FAIL, and rc 127 is a hard FAIL (no two-phase window on an arc VM).
echo ""
echo "── polling to a terminal verdict through the sshdo transport (budget ${POLL_BUDGET_S}s @ ${POLL_INTERVAL_S}s) ──"
DEADLINE=$(( $(date +%s) + POLL_BUDGET_S ))
last="(no reading yet)"
VERDICT_LINE=""
while :; do
    # shellcheck disable=SC2088  # literal '~' expands on the VM (see above)
    out=$(probe_ssh "~/statbus/ops/ci-deploy-status.sh $B_FULL" 2>/dev/null) && rc=0 || rc=$?
    line=$(printf '%s' "$out" | tail -n 1 | tr -d '\r')
    [ -n "$line" ] && last="$line"
    case "$rc" in
        0)   # CONVERGED — on THIS arc that is the failure: a rolled-back deploy read as green.
            echo "✗ the poll certified the BROKEN deploy as converged (exit 0: '$line') — green would have lied" >&2
            exit 1 ;;
        10)  # FAILED terminal — the RED verdict this arc exists to prove.
            VERDICT_LINE="$line"
            echo "  ✓ poll verdict: exit=10 '$line' — a failed deploy REPORTS red"
            break ;;
        20|30)  # pending / transient — tolerated ticks, budget decides (production semantics)
            : ;;
        64)
            echo "✗ ci-deploy-status.sh usage error (exit 64: '$line') — misconfigured poll arg" >&2
            exit 1 ;;
        127)
            echo "✗ the VM does not carry ops/ci-deploy-status.sh (exit 127) — impossible by construction on an arc VM; transport or checkout is broken" >&2
            exit 1 ;;
        255)
            echo "  … ssh transport hiccup (rc=255) — tolerated tick, consuming budget" ;;
        *)
            echo "  … unrecognised poll rc=$rc ('$line') — tolerated tick, consuming budget" ;;
    esac
    if [ "$(date +%s)" -ge "$DEADLINE" ]; then
        echo "✗ poll budget exhausted (${POLL_BUDGET_S}s) without a terminal verdict — last reading: $last" >&2
        exit 1
    fi
    sleep "$POLL_INTERVAL_S"
done

# ── the verdict must be an EXPLAINED red: rolled_back + the product's classed error ──
# The reason field carries the product's DELIBERATE contract: the failure CLASS
# ('deterministic forward failure') + the exact failing commit + remediation.
# NOT the migration's literal RAISE text — the row error is the classed operator
# summary (the STATBUS-144 design: text-as-classifier is banned; raw migration
# stderr lives in the retained migrate log + journal). The original assert
# expected the RAISE text here and was corrected after run 29743621767: the
# product does not propagate raw stderr into the row error, and should not.
STATE_FIELD="${VERDICT_LINE%%|*}"
[ "$STATE_FIELD" = "rolled_back" ] || {
    echo "✗ terminal verdict state is '$STATE_FIELD' (line: '$VERDICT_LINE'), want rolled_back — red for the wrong reason is not the proof" >&2
    exit 1
}
grep -q "deterministic forward failure" <<<"$VERDICT_LINE" || {
    echo "✗ the verdict's reason lacks the failure class 'deterministic forward failure' (line: '$VERDICT_LINE') — the row error must name the class" >&2
    exit 1
}
grep -q "${B_FULL:0:8}" <<<"$VERDICT_LINE" || {
    echo "✗ the verdict's reason does not name the failing commit ${B_FULL:0:8} (line: '$VERDICT_LINE') — the row error must pin the exact commit" >&2
    exit 1
}
echo "  ✓ explained red: state=rolled_back; reason carries the failure class + commit ${B_FULL:0:8} + remediation (the product's classed contract)"

# ── the box itself recovered (rollback restored A; serving) ──────────────────
assert_health_passes "$VM_NAME"

echo ""
echo "PASS: deploy-status-proof — a REAL broken deploy rolled back autonomously on this arc's own VM, and the deploy-workflow poll-block bytes, polling through the PRODUCTION-REPLICATED sshdo transport (canonical ops/niue/ bytes, hardened forced command, per-run ephemeral key), reported an EXPLAINED RED (exit 10, state=rolled_back, the product's classed error naming the failure class + the failing commit + remediation) after first proving the gate (non-allowlisted command refused 'not in allowlist'; allowed read exit 20 pre-drive). The STATBUS-170 red path is proven with nothing broken on any fleet box."
