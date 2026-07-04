#!/bin/bash
# Scenario: 3-postswap-resume-died-parked  (STATBUS-044, PARK-SCENARIO ASSERTION SPEC)
#
# Renamed from the deleted 3-postswap-resume-died-rollback.sh (STATBUS-099,
# 2026-06-19): that file asserted a ROLLBACK terminal and was deleted as
# product-impossible against the code as it stood then (resumePostSwap's
# self-heal canary converged before any re-kill; grounded by VM-run
# 27820228835). STATBUS-046 (D3, shipped 2026-07-03) added a genuinely NEW
# mechanism since that deletion — the crash-resume death budget
# (cli/internal/upgrade/recovery_escalation.go: resumeEscalation) — that
# PARKS a persistently-failing at-target forward attempt instead of looping
# loud forever or rolling back. This file is a FRESH build against that new
# mechanism, not a resurrection of the deleted rollback-asserting file. The
# terminal here is PARKED, then UN-PARKED — never rolled_back.
#
# REBUILT (STATBUS-044 comment #6, King-approved 2026-07-04, mechanic):
# the park-oracle VM campaign (12 runs, comment #4/#5) proved the ORIGINAL
# construction — killing at flag.step=="migrate-up" inside applyPostSwap —
# targets a window the real system essentially never reaches on a resume.
# Migrations actually apply in the BOOT-TIME schema catch-up (`sb migrate up`
# at service.go Run + the install ladder, the rc.65 schema-skew guard),
# which runs BEFORE recoverFromFlag/resumePostSwap on every recovery boot —
# so by the time applyPostSwap's own StepMigrateUp (3.5) runs, the working
# tree is already at target and there is nothing left to apply; that step is
# a no-op. Worse: a migration that crash-loops the box on every restart did
# so in the boot window, UNCOUNTED by the death budget (the rune class, in
# exactly the window heavy migrations run). commit cc660280f closed that gap
# (RecoveryBudgetGuard: count + consult BEFORE the boot migrate, stamp
# StepBootMigrate around it, parked rows skip the boot migrate). THIS
# rebuild targets that real, now-covered window instead.
#
# Assertion spec: STATBUS-044 comment #1 (architect, 2026-07-03), with the
# two substitutions comment #6 calls for: the same-step-twice message names
# "boot-migrate" (not "migrate-up"), and the parked-skip log line moves to
# the boot path (RecoveryBudgetGuard's own line, not resumePostSwap's).
#
# Also folds in STATBUS-131 AC#3 (cheap, per the mechanic's dispatch): the
# UPGRADE_CALLBACK siren is configured via .env.config ONLY — no post-kill
# .env injection hack. STATBUS-131 (shipped a5b9474cd, this same day) made
# UPGRADE_CALLBACK a first-class .env.config -> .env carry-through key, so
# it now survives every `sb config generate` call the recovery boots below
# make; the siren-once assertion is therefore also the empirical proof that
# fix actually holds under `sb config generate` running repeatedly across
# three real recovery boots, not just under the two synthetic unit tests.
#
# ─────────────────────────────────────────────────────────────────────────
# MECHANISM — direct state fabrication, no dispatch, no claim gate
# ─────────────────────────────────────────────────────────────────────────
# Unlike the original construction (which scheduled a row and let the LIVE
# daemon claim + dispatch it), this scenario fabricates the RESUME state
# DIRECTLY on disk/DB (lib/data-helpers.sh: fabricate_resume_state):
#   - an in_progress public.upgrade row (chk_upgrade_state_attributes'
#     in_progress arm: scheduled_at + started_at NOT NULL, completed_at +
#     rolled_back_at NULL), and
#   - a service-held forward recovery flag (Holder=service, Phase=post_swap
#     per the architect's explicit reminder — either phase is safe under the
#     shipped F1 parked-skip fix, but post_swap keeps the assertion surface
#     identical to comment #1's spec; CommitSHA=HEAD so Service.Run's
#     recovery-boot checkout is a no-op) with a DEAD pid.
# The "dead pid" is diagnostic-only — the real mutex is the kernel flock,
# which nobody holds since fabrication never opens/locks the file.
# RecoveryBudgetGuard's own acquireFlock call succeeds immediately on the
# very next boot, exactly as it would after a genuine process death. There
# is no claim gate to satisfy (docker_images_status / release_builds_status
# are irrelevant here — no discover/dispatch touches this row at all; it is
# manufactured already in_progress) and no LIVE daemon needs to cooperate
# before the kill sequence starts.
#
# THE STALL: alongside the row+flag, one synthetic migration file
# (migrations/<far-future-version>_park_scenario_boot_migrate_stall.up.sql,
# body `SELECT pg_sleep(3600);`) is the SOLE pending migration once real
# migrations between INSTALL_VERSION and HEAD have applied. `sb migrate up`
# (boot-migrate-up, service.go ~1909) applies ALL pending migrations in
# version order — the real backlog first (fast), then this one (a full hour)
# — so every recovery boot that reaches the boot migrate hangs there
# reliably, well within the poll budget below.
#
# STEADY-STATE FABRICATION, NOT SELF-SHIP (architect ruling, 2026-07-05, r14
# autopsy — do not "simplify" this pre-apply step away): before the kill
# sequence, this scenario explicitly pre-applies the real migration delta
# (`./sb migrate up`, using the already-uploaded HEAD binary against the
# already-checked-out HEAD tree) BEFORE the stall migration file is even
# written. This is load-bearing, not cosmetic: (i) without it, the
# recovery_attempts/recovery_parked_at/recovery_parked_reason columns don't
# exist until boot-migrate-up applies them DURING pass 1, so pass 1's
# RecoveryBudgetGuard hits the SQLSTATE 42703 fail-open path and never
# actually counts — the whole arithmetic shifts down one (park at
# attempts==2, not 3), and that shift is TIME-BOMBED: it silently reverts to
# 3 the day INSTALL_VERSION itself already ships those columns. A "2 or 3"
# tolerance would hide that drift AND mask a genuine dying-step write-ahead
# break, so the assertions below pin attempts==3 with NO tolerance — the
# steady-state pre-apply is what makes that pin true unconditionally. (ii)
# Running HEAD's `./sb migrate up` directly while the OLD release's daemon
# merely idles (not yet restarted) is safe: binary and working tree are
# BOTH already at HEAD by this point, the recovery-columns migration is
# purely additive (ADD COLUMN ... DEFAULT), the old binary's own queries
# never reference those columns by name, and migrate's advisory lock means
# nothing else is concurrently touching migrations (the old daemon isn't
# mid-recovery). See the pre-apply call site (Phase 3 below) for the full
# trace.
#
# ORPHAN NOTE (why pg_sleep(3600), not a short sleep, is safe): SIGKILLing
# the daemon PID does NOT kill the `sb migrate up` subprocess it spawned —
# docker-exec doesn't forward SIGKILL (task #14; see migrate_orphan.go), so
# each killed attempt's migrate-up (and its in-container psql running
# pg_sleep) is orphaned and keeps running independently. This is harmless
# here: (a) kill #2's fresh `sb migrate up` either re-runs pg_sleep directly
# or blocks acquiring the migrate_up advisory lock behind kill #1's still-
# running orphan — EITHER WAY it stays observably hung at flag.step==
# "boot-migrate", which is all the poll+kill mechanism needs; (b) pass 3
# PARKS inside RecoveryBudgetGuard BEFORE ever calling boot-migrate-up, so it
# never touches the orphans at all; (c) the un-park terminal (Phase 9 below)
# deletes the stall migration FIRST, and `./sb install`'s own pre-detect
# cleanOrphanSessions (cli/cmd/install.go) terminates any lingering orphaned
# migrate-sql backends (Phase 1's >2-minute-old heuristic — by Phase 9 the
# orphans are many minutes old) before the fresh clean boot-migrate runs.
#
# Also required (found run 7 of the original campaign, after 6 prior runs
# eliminated every other cause): the fetch+checkout-HEAD stage right after
# upload_sb_to_vm (mirrors 0-happy-upgrade.sh:118 verbatim). INSTALL_VERSION's
# release clone is `--depth 1`, so without an explicit fetch of HEAD,
# `./sb config generate`'s freshness check cannot resolve the uploaded
# binary's embedded HEAD commit in that shallow tree ("bad object").
#
# ─────────────────────────────────────────────────────────────────────────
# SCENARIO SHAPE
# ─────────────────────────────────────────────────────────────────────────
#   1. Install at INSTALL_VERSION. Populate demo data, snapshot.
#   2. Upload the HEAD sb binary; fetch + checkout HEAD in the working tree
#      (bad-object guard, see above). Configure UPGRADE_CALLBACK in
#      .env.config (STATBUS-131 AC#3 — survives every config generate from
#      here on; no more post-kill .env timing hack needed).
#   3. Pre-apply the real migration delta (`./sb migrate up`, STEADY-STATE
#      fabrication — see the header note above; SEQUENCE IS LOAD-BEARING),
#      THEN write the synthetic pg_sleep(3600) stall migration, THEN
#      fabricate the in_progress row + service-held post_swap flag (dead
#      pid).
#   4. Restart the unit — this single restart both swaps the running binary
#      onto HEAD AND is pass 1: RecoveryBudgetGuard finds the fabricated
#      flag, counts attempt=1 (deaths=0, always continues), stamps
#      flag.step="boot-migrate", boot-migrate-up starts applying pending
#      migrations and hangs on the synthetic one.
#   5. Kill #1: poll for flag.step=="boot-migrate", SIGKILL the daemon.
#   6. Wait for the unit to auto-restart (systemd RestartSec=30) → pass 2:
#      RecoveryBudgetGuard(2, deathStep="boot-migrate", priorDeathStep="")
#      → sameStepTwice false (priorDeathStep empty) → continue; re-stamps
#      "boot-migrate"; boot-migrate-up runs again and hangs again (directly,
#      or behind kill #1's orphan's advisory lock — either way, hung).
#   7. Kill #2: same poll+kill.
#   8. Wait for restart → pass 3: RecoveryBudgetGuard(3, "boot-migrate",
#      "boot-migrate") → sameStepTwice TRUE → PARKS immediately, INSIDE the
#      guard, BEFORE boot-migrate-up is ever called again — no third kill
#      needed, and the orphans from kills #1/#2 are never touched by this
#      pass. Siren fires (STATBUS_EVENT=parked) via the .env.config-
#      configured UPGRADE_CALLBACK.
#   9. Assert the PARK STATE (spec items 1-5, "boot-migrate" substituted).
#  10. Two EXTRA systemd restarts — assert each is skipped (RecoveryBudget-
#      Guard's own "is PARKED — skipping boot migrate" line, the boot-path
#      substitution comment #6 calls for), no attempts increment, no
#      additional siren.
#  11. UN-PARK via the install arm (spec item 6, the happy/preferred
#      terminal): delete the synthetic stall migration first (so the fresh
#      attempt's boot-migrate has nothing left to hang on), then run
#      `./sb install`. Its pre-detect cleanOrphanSessions clears any
#      lingering orphaned migrate-sql backends from kills #1/#2; the fresh
#      un-parked attempt's boot-migrate is then genuinely clean, and the
#      full resumePostSwap pipeline (containers are still on
#      INSTALL_VERSION's images — the expected post-swap "mismatched" state,
#      never having been touched by this fabrication) runs to completion.
#      Assert: UN-PARKED log line, parked_at NULL, recovery_attempts==1,
#      terminal state='completed', health passes, data intact.
#
#   Item 7 of the original spec (the NOTIFY/RunSchedule un-park arm) is NOT
#   covered — architect's spec says "install arm at minimum"; covering both
#   arms would require a SECOND full park cycle to reach a fresh parked row
#   to un-park via NOTIFY instead, roughly doubling this scenario's runtime.
#   Flagged as a deliberate scope cut, not an oversight.
#
# Hetzner-runnability:
#   BUILD-ONLY. Not run on a paid VM yet (sequenced separately per the
#   foreman/architect). The direct-fabrication + external-SIGKILL-gated-on-
#   flag-step mechanism is novel to this rebuild — the first VM run is the
#   real empirical test of the poll timing and the orphan-migrate reasoning
#   documented above.
#
# Usage:
#   INSTALL_VERSION=v2026.05.2 HCLOUD_LOCATION=fsn1 \
#     ./test/install-recovery/scenarios/3-postswap-resume-died-parked.sh \
#     statbus-recovery-3-postswap-resume-died-parked

set -euo pipefail

VM_NAME="${1:-statbus-recovery-3-postswap-resume-died-parked}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.2}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
# Budget for each "wait for flag.step to reach boot-migrate" poll.
# RecoveryBudgetGuard stamps the step right after EnsureDBUp + connect +
# advisory lock + LISTEN + READY=1 — no image-pull/reconnect in this path
# (unlike the original migrate-up construction) — but a cold VM's
# `docker compose up -d db` + `sb config generate` can still take a while.
STEP_WAIT_BUDGET_S="${STEP_WAIT_BUDGET_S:-180}"
# systemd RestartSec=30 (ops/statbus-upgrade.service) + boot/reconnect
# overhead before the flag is even readable again.
RESTART_WAIT_BUDGET_S="${RESTART_WAIT_BUDGET_S:-180}"
PARK_WAIT_BUDGET_S="${PARK_WAIT_BUDGET_S:-180}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Scenario: 3-postswap-resume-died-parked  (STATBUS-044/046 park-not-loop, boot-migrate)"
echo "  Initial release: $INSTALL_VERSION → upgrade target: HEAD"
echo "════════════════════════════════════════════════════════════════"

HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)
echo "  HEAD: $HEAD_SHA ($(echo "$HEAD_SHA" | cut -c1-8))"

UPGRADE_UNIT="statbus-upgrade@statbus.service"
FLAG_PATH='~/statbus/tmp/upgrade-in-progress.json'
CALLBACK_LOG='/tmp/park-callback-log.txt'
STALL_MIGRATION_FILE='20990101000000_park_scenario_boot_migrate_stall.up.sql'

# ─────────────────────────────────────────────────────────────────────────
# helpers local to this scenario
# ─────────────────────────────────────────────────────────────────────────

# read_flag_field <field> — generic flag-JSON field reader (grep/sed — no
# assumption that jq is installed on the VM). Empty string if the flag is
# absent or the field isn't present (Step/PriorDeathStep are `omitempty`).
# The two field names ("step" / "prior_death_step") don't collide: the
# character immediately before "step" in "prior_death_step" is '_', not '"',
# so `grep '"step":'` never matches a prior_death_step line.
read_flag_field() {
    local field="$1"
    VM_EXEC bash -c "grep '\"$field\":' $FLAG_PATH 2>/dev/null | sed -E 's/.*\"$field\": *\"([^\"]*)\".*/\1/'" 2>/dev/null | tr -d ' \r\n'
}
read_flag_step() { read_flag_field "step"; }
# read_flag_prior_death_step — the field RecoveryBudgetGuard rolls
# Step→PriorDeathStep into on EVERY continuing pass (architect verdict R1,
# 2026-07-04): unlike "step" (which the guard re-stamps to "boot-migrate" on
# EVERY continuing pass, so it shows pass-N-minus-1's residual value the
# INSTANT the new process appears, well before pass N's own guard has run),
# "prior_death_step" only becomes "boot-migrate" once pass 2's stamp
# actually executes — a pass-2-unique transition, and one written in the
# SAME mutateHeldFlag call as the (already-committed) recovery_attempts
# increment. See kill #2's gate below for why this matters.
read_flag_prior_death_step() { read_flag_field "prior_death_step"; }

# daemon_pid — the live upgrade-service Go process PID, or empty if not
# running. Mirrors wedge-helpers.sh's simulate_sigkill_upgrade_service
# process-discovery (pgrep -f "sb upgrade service").
daemon_pid() {
    VM_EXEC bash -c 'pgrep -f "sb upgrade service" 2>/dev/null | head -1' 2>/dev/null | tr -d ' \r\n'
}

# _wait_for_flag <reader_fn> <label> <target> <budget_s> — generic poll loop
# (every 1s) for a flag-JSON field (read via <reader_fn>) to equal <target>.
# Fails LOUD (non-zero, diagnostic dump) on timeout rather than silently
# racing past — see the MECHANISM header comment for why this is a real
# (bounded, diagnosable) timing dependency rather than a deterministic
# code-level trigger. Shared by the step-gate (kill #1) and prior_death_step-
# gate (kill #2) wrappers below.
_wait_for_flag() {
    local reader_fn="$1" label="$2" target="$3" budget="$4"
    local start now elapsed val
    start=$(date +%s)
    while true; do
        now=$(date +%s)
        elapsed=$((now - start))
        val=$("$reader_fn")
        if [ "$val" = "$target" ]; then
            echo "  ✓ flag.$label == '$target' (t+${elapsed}s)"
            return 0
        fi
        if [ "$elapsed" -ge "$budget" ]; then
            echo "✗ flag.$label never reached '$target' within ${budget}s (last observed: '${val:-<absent>}')" >&2
            echo "  This means either the recovery boot never reached RecoveryBudgetGuard, or it raced" >&2
            echo "  past boot-migrate faster than this 1s poll could observe — the scenario's external-" >&2
            echo "  kill mechanism (see the MECHANISM header comment) depends on catching this window." >&2
            echo "  Diagnostic flag dump:" >&2
            VM_EXEC bash -c "cat $FLAG_PATH 2>/dev/null" >&2 || true
            return 1
        fi
        sleep 1
    done
}
# wait_for_flag_step <target_step> <budget_s> — kill #1's gate: the
# fabricated flag starts step-empty, so ""→"boot-migrate" is a genuine fresh
# transition on the FIRST pass. STAYS on "step" per the architect verdict
# (only kill #2 needed the prior_death_step regate — see below).
wait_for_flag_step() { _wait_for_flag read_flag_step "step" "$1" "$2"; }
# wait_for_flag_prior_death_step <target> <budget_s> — kill #2's gate
# (architect verdict R1, 2026-07-04, fixing a real red): gating kill #2 on
# flag.step=="boot-migrate" is WRONG — pass 1's stamp leaves that value on
# disk, so it is satisfied by PASS-1 RESIDUE the instant pass 2's new PID
# appears (~2s), well before pass 2's own RecoveryBudgetGuard has even run
# (~4-10s: config-generate → EnsureDBUp → connect → advisory lock → LISTEN →
# READY precede it). Kill #2 would then land BEFORE pass 2's increment, going
# UNCOUNTED — the next boot is arithmetically pass 2 again, stalls, and
# Phase 5's park-wait times out. Gating on prior_death_step instead is
# pass-2-unique (empty through all of pass 1, becomes "boot-migrate" only
# once pass 2's stamp runs) and is written in the SAME mutateHeldFlag call as
# the (already-committed, ordered-before) recovery_attempts increment — so
# observing it on disk guarantees the increment already landed.
wait_for_flag_prior_death_step() { _wait_for_flag read_flag_prior_death_step "prior_death_step" "$1" "$2"; }

# wait_for_active_pg_sleep <budget_s> — kill #1's SECOND, additional gate
# (architect verdict R2, 2026-07-04, avoiding a confusing red): flag.step==
# "boot-migrate" alone fires ~1s after the stamp — potentially still INSIDE
# the real migration delta (~9 migrations between INSTALL_VERSION and HEAD,
# applying in ~6s), not yet in the stall. A kill landing in migrate.go's
# after-commit-before-record window on a REAL migration produces an
# unrelated "relation already exists" → class-B park with the WRONG reason,
# not the same-step park this scenario asserts. Polling for an ACTIVE backend
# running our exact pg_sleep(3600) statement proves the real delta has fully
# committed and boot-migrate-up is now executing the STALL migration's own
# transaction. Deliberately NOT applied to kill #2 (see the call site below):
# pass 2 has ONLY the stall migration pending, and kill #1's own orphaned
# pg_sleep backend (docker-exec doesn't forward SIGKILL — see the MECHANISM
# header's orphan note) would satisfy this gate spuriously even before pass
# 2's own fresh migrate-up reaches its pg_sleep (it may instead be blocked
# behind the orphan on the migrate_up advisory lock — also a valid hang, but
# this gate would then race ahead of it for no reason).
wait_for_active_pg_sleep() {
    local budget="$1"
    local start now elapsed count
    start=$(date +%s)
    while true; do
        now=$(date +%s); elapsed=$((now - start))
        count=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND query LIKE 'SELECT pg_sleep(3600)%';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n')
        if [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -ge 1 ]; then
            echo "  ✓ active pg_sleep(3600) backend observed (t+${elapsed}s) — real migration delta committed, inside the stall's own tx"
            return 0
        fi
        if [ "$elapsed" -ge "$budget" ]; then
            echo "✗ no active pg_sleep(3600) backend observed within ${budget}s — either the real migration delta is still applying or the stall migration never started" >&2
            VM_EXEC bash -c "cd ~/statbus && echo \"SELECT pid, state, query FROM pg_stat_activity WHERE datname = current_database();\" | ./sb psql -t -A" >&2 || true
            return 1
        fi
        sleep 1
    done
}

# kill_daemon_when <wait_fn> <target> [extra_gate_fn] — wait for <wait_fn>
# (one of the flag-field gates above) to observe <target>, optionally wait
# for a SECOND gate (<extra_gate_fn>, taking only a budget arg — R2's
# active-pg_sleep check, kill #1 only), then SIGKILL the live daemon PID.
# Fails loud if the process isn't found (the gate observation and the PID
# lookup are two separate reads — a process that dies on its own between
# them is a real race, but the subsequent restart-wait step would then fail
# loudly too, so this is not a silent-pass path). Sets the global
# LAST_KILLED_PID (mirrors arc-helpers.sh's ARC_DISPATCH_RC global-output
# convention) so wait_for_restart can confirm the NEXT observed PID is
# genuinely a different (new) process, not a not-yet-reaped stale pgrep
# match of the process we just killed.
LAST_KILLED_PID=""
kill_daemon_when() {
    local wait_fn="$1" target="$2" extra_gate="${3:-}"
    "$wait_fn" "$target" "$STEP_WAIT_BUDGET_S" || return 1
    if [ -n "$extra_gate" ]; then
        "$extra_gate" "$STEP_WAIT_BUDGET_S" || return 1
    fi
    local pid
    pid=$(daemon_pid)
    if [ -z "$pid" ]; then
        echo "✗ gate satisfied ($wait_fn -> '$target') but no live 'sb upgrade service' process found to kill" >&2
        return 1
    fi
    echo "  killing upgrade-service PID=$pid (gate: $wait_fn -> '$target'${extra_gate:+, extra_gate: $extra_gate})"
    VM_EXEC bash -c "kill -9 $pid" 2>/dev/null || true
    # shellcheck disable=SC2034  # read by wait_for_restart after this call
    LAST_KILLED_PID="$pid"
    return 0
}

# wait_for_restart <budget_s> [prev_pid] — poll for the daemon process to
# come back alive after a kill (systemd Restart=always, RestartSec=30). When
# prev_pid is given, requires the observed PID to DIFFER from it — otherwise
# a not-yet-reaped stale pgrep match of the just-killed process would read
# as "restarted" one poll cycle early.
wait_for_restart() {
    local budget="$1" prev_pid="${2:-}"
    local start now elapsed pid
    start=$(date +%s)
    while true; do
        now=$(date +%s); elapsed=$((now - start))
        pid=$(daemon_pid)
        if [ -n "$pid" ] && { [ -z "$prev_pid" ] || [ "$pid" != "$prev_pid" ]; }; then
            echo "  ✓ upgrade-service restarted, PID=$pid (t+${elapsed}s)"
            return 0
        fi
        if [ "$elapsed" -ge "$budget" ]; then
            echo "✗ upgrade-service did not restart (with a new PID) within ${budget}s" >&2
            VM_EXEC systemctl --user status "$UPGRADE_UNIT" --no-pager -l 2>/dev/null | tail -30 >&2 || true
            return 1
        fi
        sleep 2
    done
}

# recovery_row_cols — SELECT the three recovery_* columns + state for the
# latest upgrade row, pipe-separated.
recovery_row_cols() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state, recovery_attempts, recovery_parked_at IS NOT NULL, COALESCE(recovery_parked_reason,'') FROM public.upgrade ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A -F'|'" 2>/dev/null | tr -d '\r'
}

echo ""
echo "── initial install at $INSTALL_VERSION ──"
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

echo ""
echo "── populating demo data ──"
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-trigger data snapshot: $DATA_SNAPSHOT"
assert_demo_data_present "$VM_NAME"

# ─────────────────────────────────────────────────────────────────────────
# Phase 3 — stage the HEAD binary + working tree, configure the callback,
# then fabricate the resume state directly (no dispatch, no claim gate —
# see the MECHANISM header comment).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── uploading HEAD sb binary ──"
upload_sb_to_vm "$VM_NAME"

# Fetch + checkout HEAD in the VM's working tree (mirrors 0-happy-upgrade.sh:118
# VERBATIM). INSTALL_VERSION is a RELEASE tag, whose install path clones
# `--depth 1 --branch v2026.05.2` — a repo containing NO master commits by
# construction. Without this stage, `./sb config generate`'s freshness check can
# never resolve the just-uploaded binary's embedded HEAD in that shallow clone
# (git cat-file on a commit the depth-1 clone never fetched → "bad object" —
# the failure mode the original campaign's run 7 hit after every other cause had
# been eliminated). Also required so RecoveryBudgetGuard's boot-migrate finds
# HEAD's actual migrations on disk (including the synthetic one we add below).
# Single-line: printf '%q' converts multi-line strings to ANSI-C $'...\n...'
# quoting, but the remote /bin/sh (dash on Ubuntu) does not expand $'...' —
# newlines collapse, breaking if/then/fi syntax. Semicolons replace newlines;
# if COND; then CMD; fi is valid single-line bash.
VM_EXEC bash -c "cd ~/statbus && if ! git cat-file -e $HEAD_SHA 2>/dev/null; then git fetch --depth 1 origin $HEAD_SHA || { echo 'FATAL: cannot fetch HEAD' >&2; exit 1; }; fi && git checkout $HEAD_SHA"

echo ""
echo "── writing the park-callback script (transferred as a FILE — see the sudo -i \$-expansion trap below) ──"
# r13 AUTOPSY (2026-07-05, foreman-verified on the kept VM 89.167.23.219) —
# two independent bugs in the ORIGINAL one-liner VM_EXEC injection, both
# fixed here:
#
# BUG 2 (why the callback script is now a FILE, not an inline VM_EXEC arg):
# VM_EXEC's transport is `sudo -i -u statbus -- ...` (vm-bootstrap.sh). sudo
# -i re-quotes the command line itself before handing it to statbus's login
# shell, and that re-quoting does not reliably protect bare `$VARNAME`
# references — parens happened to survive (so `$(date ...)` came through
# intact), but `$STATBUS_EVENT` (no parens) was silently expanded to empty
# somewhere in that reconstruction. The VM's actual .env.config ended up
# with `echo " $(date -u +%FT%TZ)"` — the event name GONE — so even with
# BUG 1 fixed, the siren-once assertion could never match. Fix: never pass
# $-containing shell text through VM_EXEC as an ARGUMENT. Build the script
# body in a LOCAL heredoc (quoted delimiter — nothing expands locally,
# except $CALLBACK_LOG which we WANT substituted now, via a deliberate
# backslash-escape split below) and scp it to the VM as a file — the $
# characters land on disk untouched, evaluated by /bin/sh only when the
# callback actually fires.
CALLBACK_SCRIPT_LOCAL=$(mktemp)
cat > "$CALLBACK_SCRIPT_LOCAL" << CALLBACKSCRIPT
#!/bin/sh
echo "\$STATBUS_EVENT \$(date -u +%FT%TZ)" >> $CALLBACK_LOG
CALLBACKSCRIPT
scp -O "${SSH_OPTS[@]}" "$CALLBACK_SCRIPT_LOCAL" root@"$VM_IP":/tmp/park-callback.sh >/dev/null
rm -f "$CALLBACK_SCRIPT_LOCAL"
ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
    'mv /tmp/park-callback.sh /home/statbus/park-callback.sh && chown statbus:statbus /home/statbus/park-callback.sh && chmod 0755 /home/statbus/park-callback.sh'
echo "  ✓ /home/statbus/park-callback.sh installed (chmod 0755)"

echo ""
echo "── configuring UPGRADE_CALLBACK via .env.config (STATBUS-131 AC#3 — survives every config generate from here on) ──"
VM_EXEC bash -c "rm -f $CALLBACK_LOG"
# BUG 1: the product-generated .env.config has NO trailing newline (its last
# written line is "ADMINISTRATOR_CONTACT=", no \n) — a naive `>> .env.config`
# GLUES onto that line ("ADMINISTRATOR_CONTACT=UPGRADE_CALLBACK=..."), so the
# landed-check below found nothing. Ensure a trailing newline first —
# expansion-proof (see BUG 2 above; the `"^$"` grep pattern does contain a
# literal dollar, but a $ immediately before a closing quote cannot begin an
# expansion in any POSIX shell layer — a grammar guarantee, unlike the
# parens-survived luck BUG 2 rightly distrusts):
# `tail -c1 | grep -q "^$"` matches iff the last byte
# IS a newline (or the file is empty, in which case `tail -c1` outputs
# nothing and grep also finds no match, so the `||` fires and prepends a
# harmless leading blank line — same safe outcome as the "not a newline"
# case). Only NOW is UPGRADE_CALLBACK set to the plain, $-free script PATH
# (never the raw command containing $ references) — safe to append via the
# ordinary VM_EXEC mechanism since there's nothing left for any shell layer
# to mis-expand.
VM_EXEC bash -c 'cd ~/statbus && (tail -c1 .env.config | grep -q "^$" || printf "\n" >> .env.config) && printf "UPGRADE_CALLBACK=/home/statbus/park-callback.sh\n" >> .env.config'
VM_EXEC bash -c "grep '^UPGRADE_CALLBACK=' ~/statbus/.env.config" || { echo "✗ UPGRADE_CALLBACK injection did not land in .env.config" >&2; exit 1; }

echo ""
echo "── pre-applying the real migration delta (STEADY-STATE fabrication — architect ruling, 2026-07-05, r14 autopsy) ──"
# SEQUENCE IS LOAD-BEARING (do not reorder): checkout HEAD -> `./sb migrate up`
# (THIS step) -> write the stall migration -> fabricate_resume_state -> restart.
# If the stall file existed BEFORE this pre-apply, this very invocation would
# hang on pg_sleep(3600) for an hour (`sb migrate up` applies ALL pending
# migrations in version order, our synthetic one included, the moment it's on
# disk) — so the stall file must not exist yet when this runs.
#
# WHY STEADY-STATE, NOT SELF-SHIP (r14 failed on the self-ship shape): without
# this pre-apply, the recovery_attempts/recovery_parked_at/recovery_parked_reason
# columns (migration 20260703210000, part of the real delta between
# INSTALL_VERSION and HEAD) do not exist until boot-migrate-up applies them
# DURING pass 1 — so pass 1's RecoveryBudgetGuard hits the SQLSTATE 42703
# fail-open path (service.go: "proceeding fail-open with a single attempt")
# and never actually increments recovery_attempts; only pass 2 gets the FIRST
# real increment. That shifts the whole arithmetic down by one: same-step-twice
# then parks at attempts==2, not 3 — and this is TIME-BOMBED, not just an
# off-by-one to tolerate: the day INSTALL_VERSION itself already ships those
# columns (any release baseline including STATBUS-046), the fail-open path
# never triggers and the arithmetic silently flips back to 3. A "2 or 3"
# tolerance would paper over that drift AND mask a genuine dying-step
# write-ahead break (the same failure the pinned same-step-twice regex below
# already guards). Pre-applying the real delta NOW — while the OLD release's
# daemon is merely idling in its normal ticker loop, not mid-recovery — makes
# the columns exist BEFORE pass 1 ever runs, so the increment always lands
# cleanly on pass 1: attempts==3 at park, every time, regardless of which
# release happens to be INSTALL_VERSION. Running HEAD's `./sb migrate up`
# directly (not via the daemon) here is safe: binary and working tree are
# BOTH already at HEAD (upload_sb_to_vm + the checkout above), the recovery-
# columns migration is purely additive (ADD COLUMN ... DEFAULT), the OLD
# binary's still-idling queries never reference those columns by name, and
# migrate's own advisory lock means there is nothing else touching migrations
# concurrently (the old daemon isn't running its own migrate-up).
# config generate FIRST — mirrors the real recovery-boot order (the daemon
# runs config-generate before boot-migrate). The release-era .env lacks keys
# the HEAD compose file requires (r15: REST_ADMIN_BIND_ADDRESS "must be set"
# → psql/migrate exit 1 at "ensure migration table"), so the HEAD binary must
# regenerate .env before any compose-touching command. This is also a live
# STATBUS-131 proof leg: the .env.config-configured UPGRADE_CALLBACK must
# survive this very generate into .env (verified on the r15 autopsy VM).
VM_EXEC bash -c "cd ~/statbus && ./sb config generate"
# timeout 600: migrate.Up itself is unbounded (MigrateUpTimeout is imposed by
# the boot-migrate CALLERS, not the CLI) — a wedged pre-apply should fail this
# phase with a named error, not eat the scenario's global budget.
VM_EXEC bash -c "cd ~/statbus && timeout 600 ./sb migrate up --verbose"

echo ""
echo "── writing the synthetic stall migration (sole pending migration once real ones catch up: pg_sleep(3600)) ──"
VM_EXEC bash -c "cd ~/statbus && printf 'SELECT pg_sleep(3600);\n' > migrations/$STALL_MIGRATION_FILE"
VM_EXEC bash -c "test -f ~/statbus/migrations/$STALL_MIGRATION_FILE" || { echo "✗ stall migration file did not land" >&2; exit 1; }
echo "  ✓ migrations/$STALL_MIGRATION_FILE written"

echo ""
echo "── fabricating the in_progress row + service-held post_swap flag (dead pid) ──"
fabricate_resume_state "$VM_NAME" "$HEAD_SHA" >/dev/null

# ─────────────────────────────────────────────────────────────────────────
# Phase 4 — restart onto HEAD (this single restart also IS pass 1, since the
# fabricated flag is already on disk): kill #1 (RecoveryBudgetGuard attempt=1,
# the "planned" first pass — always continues) and kill #2 (attempt=2). See
# the MECHANISM header comment for why an external kill rather than
# inject.KillHere. Per the architect's 2026-07-04 verdict, the two kills use
# DIFFERENT gates (R1 + R2 — see the wait_for_flag_step /
# wait_for_flag_prior_death_step / wait_for_active_pg_sleep comments above):
# kill #1 gates on flag.step=="boot-migrate" PLUS an active-pg_sleep check
# (proves it lands inside the stall's own tx, not mid-real-migration); kill
# #2 gates on flag.prior_death_step=="boot-migrate" (pass-2-unique — gating
# on "step" there would fire on pass 1's residual stamp before pass 2's own
# guard has even run, going uncounted).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── restarting upgrade-service unit onto HEAD (discovers the fabricated flag = pass 1) ──"
vm_restart_unit "statbus-upgrade@statbus.service"
echo "  ✓ unit active on the HEAD binary"

echo ""
echo "── kill #1: waiting for flag.step=='boot-migrate' + an active pg_sleep(3600) backend (attempt=1) ──"
kill_daemon_when wait_for_flag_step "boot-migrate" wait_for_active_pg_sleep
wait_for_restart "$RESTART_WAIT_BUDGET_S" "$LAST_KILLED_PID"

echo ""
echo "── kill #2: waiting for flag.prior_death_step=='boot-migrate' (attempt=2) ──"
kill_daemon_when wait_for_flag_prior_death_step "boot-migrate"
KILL2_PID="$LAST_KILLED_PID"

echo ""
echo "── waiting for restart into attempt=3 (expect same-step-twice PARK, no further kill needed) ──"
wait_for_restart "$RESTART_WAIT_BUDGET_S" "$KILL2_PID"

# ─────────────────────────────────────────────────────────────────────────
# Phase 5 — wait for the PARK to land (recovery_parked_at IS NOT NULL).
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── waiting for park (recovery_parked_at IS NOT NULL) ──"
PARK_START=$(date +%s)
while true; do
    NOW=$(date +%s); ELAPSED=$((NOW - PARK_START))
    ROW=$(recovery_row_cols)
    PARKED_FLAG=$(echo "$ROW" | cut -d'|' -f3)
    if [ "$PARKED_FLAG" = "t" ]; then
        echo "  ✓ row parked (t+${ELAPSED}s): $ROW"
        break
    fi
    if [ "$ELAPSED" -ge "$PARK_WAIT_BUDGET_S" ]; then
        echo "✗ row did not park within ${PARK_WAIT_BUDGET_S}s (last: $ROW)" >&2
        exit 1
    fi
    sleep 3
done

# ─────────────────────────────────────────────────────────────────────────
# Phase 6 — ASSERT PARK STATE (spec items 1-5, "boot-migrate" substituted)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── assert 1: row state + recovery_attempts + parked_reason (same-step-twice path, attempts==3 pinned) ──"
ROW=$(recovery_row_cols)
ROW_STATE=$(echo "$ROW" | cut -d'|' -f1)
ROW_ATTEMPTS=$(echo "$ROW" | cut -d'|' -f2)
ROW_REASON=$(echo "$ROW" | cut -d'|' -f4)
echo "  state=$ROW_STATE attempts=$ROW_ATTEMPTS reason=$ROW_REASON"

[ "$ROW_STATE" = "in_progress" ] || { echo "✗ expected state='in_progress' while parked, got '$ROW_STATE'" >&2; exit 1; }

# Pin the same-step-twice path: this scenario ALWAYS kills at the SAME step
# ("boot-migrate") both times, so the reason MUST name same-step-twice, never
# the budget-exhaust message — the budget message appearing instead would
# mean the dying-step write-ahead (RecoveryBudgetGuard's mutateHeldFlag stamp)
# broke (STATBUS-044 comment #1's explicit diagnostic: "the budget message
# showing up instead means the dying-step write-ahead broke").
echo "$ROW_REASON" | grep -qE 'two consecutive crash-deaths at step "boot-migrate".*same-step-twice' || {
    echo "✗ recovery_parked_reason does not match the same-step-twice pattern for step 'boot-migrate'" >&2
    echo "  actual: $ROW_REASON" >&2
    if echo "$ROW_REASON" | grep -q 'budget exhausted'; then
        echo "  got the BUDGET-EXHAUST message instead — the dying-step write-ahead (RecoveryBudgetGuard's stamp) likely broke" >&2
    fi
    exit 1
}
echo "  ✓ reason matches same-step-twice at step 'boot-migrate'"

# Same-step-twice parks on the resume immediately following the second
# kill WITHOUT a third boot-migrate-up run — attempts==3 exactly (see the
# MECHANISM/SCENARIO SHAPE header trace). PINNED, no tolerance (architect
# ruling, 2026-07-05, r14 autopsy): the fabrication is now STEADY-STATE —
# the recovery_* columns are guaranteed to exist BEFORE pass 1 ever runs
# (the pre-apply step above), so pass 1's RecoveryBudgetGuard increment
# ALWAYS lands cleanly (no 42703 fail-open uncounted-first-pass case). A
# "2 or 3" tolerance would mask a genuine dying-step write-ahead break —
# see the MECHANISM header's "steady-state, not self-ship" note for why the
# old tolerance existed and why it's gone.
[ "$ROW_ATTEMPTS" = "3" ] || { echo "✗ recovery_attempts=$ROW_ATTEMPTS — expected exactly 3 for the same-step-twice path (steady-state fabrication guarantees this, no tolerance)" >&2; exit 1; }
echo "  ✓ recovery_attempts=3 (same-step-twice path, pinned)"

echo ""
echo "── assert 2: unit alive-idle, NRestarts BOUNDED and FROZEN across a settle window (anti-rune, load-bearing) ──"
assert_systemd_active "$VM_NAME" "$UPGRADE_UNIT" "active"
NR_BEFORE=$(VM_EXEC systemctl --user show "$UPGRADE_UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n')
echo "  NRestarts (pre-settle) = $NR_BEFORE"
[[ "$NR_BEFORE" =~ ^[0-9]+$ ]] || { echo "✗ could not parse NRestarts (got '$NR_BEFORE')" >&2; exit 1; }
# Bound, never pin: the "restart onto HEAD" restart + 2 real kills so far (3
# restarts) plus normal systemd start/stop churn margin. NOT an exact-equality
# check (systemd's counter includes unrelated starts — anti-assertion in the
# spec).
[ "$NR_BEFORE" -le 7 ] || { echo "✗ NRestarts=$NR_BEFORE exceeds the bound of 7 after 2 kills — restart-loop pathology" >&2; exit 1; }
echo "  settling 30s, then re-checking NRestarts is UNCHANGED (parked ⇒ alive-idle, no further crash-restart cycle)..."
sleep 30
NR_AFTER=$(VM_EXEC systemctl --user show "$UPGRADE_UNIT" --property=NRestarts --value 2>/dev/null | tr -d ' \r\n')
echo "  NRestarts (post-settle) = $NR_AFTER"
[ "$NR_AFTER" = "$NR_BEFORE" ] || { echo "✗ NRestarts changed during the settle window ($NR_BEFORE → $NR_AFTER) — the unit is still crash-looping, not alive-idle" >&2; exit 1; }
echo "  ✓ NRestarts bounded ($NR_BEFORE) and frozen across the 30s settle window"

echo ""
echo "── assert 3: siren fired exactly once ──"
CALLBACK_COUNT=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
echo "  callback log line count: $CALLBACK_COUNT"
[ "$CALLBACK_COUNT" = "1" ] || { echo "✗ expected exactly 1 callback line, got $CALLBACK_COUNT" >&2; VM_EXEC bash -c "cat $CALLBACK_LOG 2>/dev/null" >&2 || true; exit 1; }
VM_EXEC bash -c "cat $CALLBACK_LOG" | grep -q "^parked " || { echo "✗ callback line does not carry STATBUS_EVENT=parked" >&2; exit 1; }
echo "  ✓ exactly one STATBUS_EVENT=parked callback fired (via the .env.config-configured UPGRADE_CALLBACK — STATBUS-131 AC#3 proof)"

echo ""
echo "── assert 4: flag file still present (parked row keeps it) ──"
VM_EXEC bash -c "ls -la $FLAG_PATH" >/dev/null 2>&1 || { echo "✗ expected flag file present while parked" >&2; exit 1; }
echo "  ✓ flag present"

echo ""
echo "── assert 5: never rolled_back ──"
[ "$ROW_STATE" != "rolled_back" ] || { echo "✗ row state is 'rolled_back' — at-target exhaust must PARK, never roll back (039)" >&2; exit 1; }
echo "  ✓ state was never rolled_back (confirmed in_progress above)"

# ─────────────────────────────────────────────────────────────────────────
# Phase 7 — two EXTRA restarts after park: each must be skipped by
# RecoveryBudgetGuard's own boot-path check (comment #6's substitution — the
# guard runs before boot-migrate on EVERY recovery boot, parked or not, so
# this line fires reliably regardless of whether resumePostSwap's own
# parked-skip also fires downstream). No attempts increment, no additional
# siren.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── two extra restarts after park: assert parked-skip (boot path), no attempts bump, no re-siren ──"
for i in 1 2; do
    echo "  extra restart #$i..."
    ATTEMPTS_BEFORE=$(recovery_row_cols | cut -d"|" -f2)
    PRE_RESTART_PID=$(daemon_pid)
    VM_EXEC systemctl --user restart "$UPGRADE_UNIT" 2>/dev/null || true
    wait_for_restart "$RESTART_WAIT_BUDGET_S" "$PRE_RESTART_PID"
    # Give the daemon a moment to run its boot sequence (RecoveryBudgetGuard →
    # skip boot-migrate → recoverFromFlag → resumePostSwap → parked-skip →
    # return) before reading state.
    sleep 5
    JOURNAL_TAIL=$(VM_EXEC bash -c "journalctl --user -u $UPGRADE_UNIT --no-pager -n 60 2>/dev/null" || echo "")
    echo "$JOURNAL_TAIL" | grep -q "is PARKED.*skipping boot migrate" || {
        echo "✗ extra restart #$i: journal does not show RecoveryBudgetGuard's parked-skip line" >&2
        echo "$JOURNAL_TAIL" | tail -20 >&2
        exit 1
    }
    echo "  ✓ extra restart #$i logged the boot-path parked-skip line"
    ATTEMPTS_AFTER=$(recovery_row_cols | cut -d"|" -f2)
    [ "$ATTEMPTS_AFTER" = "$ATTEMPTS_BEFORE" ] || {
        echo "✗ extra restart #$i: recovery_attempts changed ($ATTEMPTS_BEFORE → $ATTEMPTS_AFTER) — a parked-skip must NOT consume an attempt" >&2
        exit 1
    }
    echo "  ✓ extra restart #$i: recovery_attempts unchanged ($ATTEMPTS_AFTER)"
done
CALLBACK_COUNT_AFTER=$(VM_EXEC bash -c "wc -l < $CALLBACK_LOG 2>/dev/null" | tr -d ' \r\n' || echo "0")
[ "$CALLBACK_COUNT_AFTER" = "1" ] || { echo "✗ callback fired again across the extra restarts (count=$CALLBACK_COUNT_AFTER, expected still 1)" >&2; exit 1; }
echo "  ✓ siren still fired exactly once across both extra restarts"

# ─────────────────────────────────────────────────────────────────────────
# Phase 8 — UN-PARK via the install arm (spec item 6, preferred terminal:
# the fresh attempt COMPLETES, proving the park/un-park cycle left the
# pipeline undamaged). Delete the stall migration FIRST — the fresh attempt's
# boot-migrate must find nothing pending, or it hangs again for an hour.
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "── deleting the synthetic stall migration before un-park ──"
VM_EXEC bash -c "cd ~/statbus && rm -f migrations/$STALL_MIGRATION_FILE"
VM_EXEC bash -c "test ! -f ~/statbus/migrations/$STALL_MIGRATION_FILE" || { echo "✗ stall migration file still present after rm" >&2; exit 1; }
echo "  ✓ migrations/$STALL_MIGRATION_FILE removed"

echo ""
echo "── un-park via ./sb install (deliberate operator trigger) ──"
INSTALL_OUT=$(mktemp)
set +e
timeout "${INSTALL_BUDGET_S}s" ssh "${SSH_OPTS[@]}" statbus@"$(hcloud server ip "$VM_NAME")" \
    "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf" \
    > "$INSTALL_OUT" 2>&1
INSTALL_RC=$?
set -e
cat "$INSTALL_OUT"
echo "  ./sb install (un-park) exit: $INSTALL_RC"
[ "$INSTALL_RC" -eq 0 ] || { echo "✗ un-park install did not exit 0 (expected the fresh attempt to complete cleanly since the stall migration is gone and any orphans were cleaned)" >&2; exit 1; }

grep -qE "UN-PARKED upgrade id=[0-9]+" "$INSTALL_OUT" || {
    echo "✗ expected the 'UN-PARKED upgrade id=N' line in ./sb install's output" >&2
    exit 1
}
echo "  ✓ install logged the UN-PARKED line"
rm -f "$INSTALL_OUT"

echo ""
echo "── assert un-park + fresh-attempt convergence ──"
ROW=$(recovery_row_cols)
ROW_STATE=$(echo "$ROW" | cut -d'|' -f1)
ROW_ATTEMPTS=$(echo "$ROW" | cut -d'|' -f2)
ROW_PARKED=$(echo "$ROW" | cut -d'|' -f3)
echo "  post-unpark row: $ROW"

[ "$ROW_PARKED" = "f" ] || { echo "✗ expected recovery_parked_at IS NULL after un-park, still parked" >&2; exit 1; }
echo "  ✓ parked_at cleared"

# Exactly ONE fresh attempt: UnparkByID resets recovery_attempts to 0, then
# RecoveryBudgetGuard's fresh consult increments it to 1.
[ "$ROW_ATTEMPTS" = "1" ] || { echo "✗ expected recovery_attempts==1 after the fresh un-parked attempt, got $ROW_ATTEMPTS" >&2; exit 1; }
echo "  ✓ recovery_attempts==1 (exactly one fresh attempt)"

[ "$ROW_STATE" = "completed" ] || { echo "✗ expected the un-parked fresh attempt to reach 'completed' (stall migration removed, orphans cleaned), got '$ROW_STATE'" >&2; exit 1; }
echo "  ✓ terminal state == 'completed' — the park/un-park cycle did NOT damage the pipeline"

assert_flag_file_absent "$VM_NAME"
assert_no_orphan_backup "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"

echo ""
echo "PASS: 3-postswap-resume-died-parked (two same-step deaths at boot-migrate PARKED the upgrade — alive-idle, NRestarts bounded+frozen, siren fired exactly once via a .env.config-only UPGRADE_CALLBACK including two extra skipped restarts, never rolled_back — then ./sb install UN-PARKED it for exactly one fresh attempt, which COMPLETED cleanly, proving the pipeline is undamaged by the park/un-park cycle)"
