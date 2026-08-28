#!/bin/bash
# Arc: worker-wedge-mid-derive  (STATBUS-279)
#
# THE NORWAY WEDGE, REPRODUCED ON A REAL VM — the named path to proving
# STATBUS-264's retry-then-FATAL guard, which is recorded UNPROVEN because no
# normal upgrade exercises it (265's exemption means the reset is never refused
# on any healthy path).
#
# THE TWO INGREDIENTS, in order:
#   (1) real derive work is started and the worker is stopped MID-DERIVE,
#       leaving derive children in 'processing' with no live claimant — the
#       abandoned state the wedge was made of.
#   (2) the next upgrade runs, so a worker restarts INSIDE the upgrade's
#       read-only window and meets those rows. That is the exact collision
#       Norway hit: the worker came up 2.4 seconds before the window lifted,
#       its startup reset's `SELECT ... FOR UPDATE` was refused, the error was
#       logged, and four derive children stayed 'processing' for a week behind
#       a worker that processed every other queue daily.
#
# EXPECTED TERMINAL against current binaries (264+265 aboard since rc.10):
# PASS — the exemption lets the startup reset run inside the window, the rows
# are reclaimed, and the wedge cannot form.
#
# ★ THE RED RULE — WHY THIS ARC IS EVIDENCE AND NOT DECORATION ★
# A regression arc that has never been seen red proves only that it runs. This
# one must FAIL against a pre-265 binary before its green counts. Point
# BASE_SHA at rc.09 (or any pre-265 tag) to get that run: the fixture builds B
# FROM BASE_SHA, so BOTH sides are then pre-265 — which matters, because if
# only A were old, B's worker would carry the exemption and the arc would go
# green for the wrong reason.
#
# WHY THE MID-DERIVE STOP IS DETERMINISTIC (no sleep-tuning, no wall-clock race).
# The derive task is not raced — it is made UNABLE TO FINISH. A held
# ACCESS EXCLUSIVE lock on public.statistical_unit blocks the derive child, and
# this arc then proceeds only on an OBSERVATION (a derive% row in 'processing'
# whose backend reports wait_event_type='Lock'), never on elapsed time. The lock
# guarantees the task cannot slip past the observation window while we look.
#
# WHY THE WORKER IS *STOPPED*, NOT MERELY KILLED. The worker container carries
# `restart: unless-stopped`. A bare SIGKILL would be restarted by Docker within
# seconds — OUTSIDE the read-only window — where the startup reset succeeds on
# every binary, reclaims the rows, and destroys ingredient (1) before the
# upgrade ever runs. The arc would then pass on ANY binary, proving nothing.
# `docker compose stop -t 0` sends the kill AND leaves the container down, so
# the rows stay abandoned until the UPGRADE brings the worker back up — inside
# the window, which is the whole point.
#
# Inputs (env): BASE_SHA, B_FULL (40-hex), B_BRANCH, V_VERSION,
# SB_ARC_TRUSTED_SIGNER. VM name = $1.

set -euo pipefail

VM_NAME="${1:-statbus-arc-worker-wedge-mid-derive}"
INSTALL_BUDGET_S="${INSTALL_BUDGET_S:-900}"
TICK_WAIT_S="${TICK_WAIT_S:-120}"
DERIVE_WAIT_S="${DERIVE_WAIT_S:-300}"
HOLD_RELEASE_FILE="/tmp/arc-279-hold-lock"
HOLD_LOG="/tmp/arc-279-hold-lock.log"

: "${BASE_SHA:?BASE_SHA required}"
: "${B_FULL:?B_FULL required}"
: "${B_BRANCH:?B_BRANCH required}"
: "${V_VERSION:?V_VERSION required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/data-helpers.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/arc-helpers.sh"

# _dump_wedge_failure_diagnostics — STATBUS-296 pattern, followed from birth:
# SSH-ONLY captures first, then db-dependent captures LAST and each guarded
# individually, so a down or unreachable database reports itself as a datum
# instead of aborting the rest of the dump under this file's `set -e`. A
# diagnostics failure must never mask the assertion error that triggered it.
_dump_wedge_failure_diagnostics() {
    echo "" >&2
    echo "══════════ failure diagnostics (worker journal, container state, task rows) ══════════" >&2

    # ── SSH-only, no database ──
    echo "── worker container state ──" >&2
    VM_EXEC bash -c "cd ~/statbus && docker compose ps worker 2>&1" >&2 || echo "  (could not read compose ps)" >&2
    echo "── worker container logs (last 200 lines) ──" >&2
    VM_EXEC bash -c "cd ~/statbus && docker compose logs --no-color --tail 200 worker 2>&1" >&2 || echo "  (could not read worker logs)" >&2
    echo "── worker restart count (a crash-loop is 264-without-265's signature) ──" >&2
    VM_EXEC bash -c "cd ~/statbus && docker inspect --format '{{.RestartCount}} {{.State.Status}} {{.State.ExitCode}}' \$(docker compose ps -q worker 2>/dev/null) 2>&1" >&2 || echo "  (could not inspect the worker container)" >&2
    echo "── upgrade daemon journal (last 200 lines) ──" >&2
    VM_EXEC bash -c "journalctl --user -u statbus-upgrade@statbus.service --no-pager -n 200 2>/dev/null" >&2 || echo "  (could not read the journal)" >&2
    echo "── lock-holder log ──" >&2
    VM_EXEC bash -c "cat $HOLD_LOG 2>/dev/null || echo '(no holder log)'" >&2 || true
    echo "── flag file at exit ──" >&2
    VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json 2>/dev/null || echo '(flag absent)'" >&2 || true

    # ── database-dependent, last, each guarded ──
    echo "── worker.tasks by state ──" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state, count(*) FROM worker.tasks GROUP BY state ORDER BY state;\" | ./sb psql" >&2 \
        || echo "  (could not query worker.tasks — DB down or unreachable)" >&2
    echo "── rows still 'processing' (the wedge, if it formed) ──" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, command, worker_pid, process_start_at FROM worker.tasks WHERE state = 'processing'::worker.task_state ORDER BY id LIMIT 20;\" | ./sb psql" >&2 \
        || echo "  (could not query processing rows — DB down or unreachable)" >&2
    echo "── B's upgrade row ──" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, state, error FROM public.upgrade WHERE commit_sha = '${B_FULL:-}' ORDER BY id DESC LIMIT 1;\" | ./sb psql" >&2 \
        || echo "  (could not query B's row — DB down or unreachable)" >&2
    echo "══════════ end failure diagnostics ══════════" >&2
}

# Release the lock holder on ANY exit path, before the VM is reaped — otherwise
# a mid-arc failure leaves an ACCESS EXCLUSIVE lock held until its psql session
# dies with the VM, and every diagnostic query above would block behind it.
_release_hold() {
    VM_EXEC bash -c "rm -f $HOLD_RELEASE_FILE" >/dev/null 2>&1 || true
}

trap 'rc=$?; _release_hold; if [ "$rc" -ne 0 ]; then _dump_wedge_failure_diagnostics; fi; cleanup_vm "$VM_NAME"; exit $rc' EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  Arc: worker-wedge-mid-derive  (STATBUS-279 — abandon derive rows, then upgrade)"
echo "  A=${BASE_SHA:0:8}  B=${B_FULL:0:8}"
echo "════════════════════════════════════════════════════════════════"

# STATBUS-293: filtered to B — an unfiltered probe reads whatever row has the
# highest id, and discovery registers candidate rows at any moment.
upgrade_state() { VM_EXEC bash -c "cd ~/statbus && echo \"SELECT state FROM public.upgrade WHERE commit_sha = '$B_FULL' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"; }

# abandoned_processing_count — rows in 'processing' whose claiming backend is
# GONE. This is the wedge, asked directly and without a threshold: a task claims
# a backend by writing worker_pid = pg_backend_pid(), so a 'processing' row
# whose pid is absent from pg_stat_activity was abandoned by definition.
#
# Deliberately expressed here rather than calling worker.abandoned_processing_tasks()
# (STATBUS-267): that function does not exist on the pre-265 binaries this arc
# must run RED against, and an arc whose measurement depends on a function the
# old code lacks would fail to construct instead of failing its assertion.
abandoned_processing_count() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM worker.tasks t WHERE t.state = 'processing'::worker.task_state AND t.worker_pid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_stat_activity a WHERE a.pid = t.worker_pid AND a.datname = current_database());\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?"
}

# blocked_derive_count — derive children that are 'processing' AND whose backend
# is parked on a lock. This is the OBSERVATION the arc advances on; it is what
# makes the mid-derive stop deterministic rather than timed.
blocked_derive_count() {
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM worker.tasks t JOIN pg_stat_activity a ON a.pid = t.worker_pid WHERE t.state = 'processing'::worker.task_state AND t.command LIKE 'derive%' AND a.wait_event_type = 'Lock';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "0"
}

# ── A: install + demo data (arc_prepare_box gives installed-A, health, daemon, data) ──
arc_prepare_box
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")
echo "  pre-wedge data snapshot: $DATA_SNAPSHOT"

# Let the post-import pipeline settle first, so the derive work this arc traps
# is the work IT triggered — not an import's tail still draining, which would
# make "a derive row is processing" true before the lock was ever taken.
wait_for_worker_quiesce "$VM_NAME"

# ══════════════════════════════════════════════════════════════════════════
# INGREDIENT (1): real derive work, stopped mid-flight
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "── ingredient 1: hold a lock the derive must take ──"
# The holder writes BEGIN + LOCK into psql, then WAITS on a release file before
# writing COMMIT. psql consumes stdin as it arrives, so the transaction — and
# the lock — stays open exactly as long as the file exists. Same release-file
# idiom the stall arcs use, and the release is a file removal (deterministic),
# never an expiry.
#
# SHIPPED AS A SCRIPT, NOT AS A VM_EXEC ARGUMENT (STATBUS-021's guard). VM_EXEC
# REFUSES a multi-line argument, because the sudo -i transport mangles multi-line
# bodies and silently expands a literal `$` — and this body needs BOTH: several
# lines, and `$HOLD_RELEASE_FILE` evaluated on the VM at loop time rather than
# interpolated here. The guard caught the first version of this arc at runtime.
#
# The heredoc delimiter is QUOTED ('HOLDER') so bash does not touch the body
# locally; the two values the body needs are passed as ARGUMENTS and read as
# $1/$2 on the VM, which is the only interpolation-free way to parameterise it.
VM_SCRIPT_INLINE arc279-hold-lock "$HOLD_RELEASE_FILE" "$HOLD_LOG" <<'HOLDER'
#!/bin/bash
# arc-279 lock holder. $1 = release file, $2 = log. Backgrounds itself so the
# calling VM_SCRIPT returns immediately while the transaction stays open.
release_file="$1"
log_file="$2"
cd ~/statbus || exit 1
cat > /tmp/arc-279-hold-lock-inner.sh <<'INNER'
release_file="$1"
cd ~/statbus || exit 1
{
  echo "BEGIN;"
  echo "LOCK TABLE public.statistical_unit IN ACCESS EXCLUSIVE MODE;"
  echo "SELECT 'arc-279 lock held' AS held;"
  # psql consumes stdin as it arrives, so withholding COMMIT holds the
  # transaction — and the lock — open for exactly as long as the file exists.
  while [ -f "$release_file" ]; do sleep 1; done
  echo "COMMIT;"
} | ./sb psql
INNER
chmod 0755 /tmp/arc-279-hold-lock-inner.sh

# THE RELEASE FILE IS CREATED BY THE HOLDER ITSELF, BEFORE THE INNER SCRIPT
# STARTS — deliberately, and this is the fix for construction fault #2.
#
# It used to be a separate `VM_EXEC touch` step in the arc body. The
# VM_SCRIPT_INLINE conversion replaced the block that contained it and the touch
# was silently lost, so the file never existed: the inner loop's very first
# `[ -f ]` was false, psql received COMMIT immediately, and the lock it had just
# taken was released within milliseconds. The holder's own log proved it —
# BEGIN / LOCK TABLE / held / COMMIT with nothing in between — while the arc
# polled pg_locks for three and a half minutes for a lock that no longer existed.
#
# Creating it HERE makes "the file exists" an invariant of starting the holder
# rather than a separate step a future edit can drop again. Creation strictly
# BEFORE the background start closes the window where the inner script could
# look before the file appeared.
: > "$release_file"
[ -f "$release_file" ] || { echo "arc279-hold-lock: could not create the release file $release_file" >&2; exit 1; }

setsid nohup bash /tmp/arc-279-hold-lock-inner.sh "$release_file" > "$log_file" 2>&1 < /dev/null &
echo holder-started
HOLDER

# Confirm the lock is actually HELD before triggering work — otherwise the
# trigger could race ahead of the holder and the derive would simply complete.
_held=0
for _i in $(seq 1 60); do
    _n=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid = l.relation WHERE c.relname = 'statistical_unit' AND l.mode = 'AccessExclusiveLock' AND l.granted;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo 0)
    [ "${_n:-0}" -ge 1 ] && { _held=1; break; }
    sleep 1
done
[ "$_held" = "1" ] || { echo "✗ the ACCESS EXCLUSIVE lock was never granted — ingredient 1 cannot be constructed" >&2; exit 1; }
echo "  ✓ ACCESS EXCLUSIVE lock held on public.statistical_unit"

echo ""
echo "── trigger the REAL derive pipeline (a data edit, exactly as production does) ──"
# worker.log_base_change() fires on this UPDATE, writes the change log, enqueues
# 'collect_changes' and notifies — which spawns derive_units_phase and its
# children. The real trigger path, not a synthetic INSERT into worker.tasks, so
# the rows this arc abandons are real derive children exactly as Norway's were.
VM_EXEC bash -c "cd ~/statbus && echo \"UPDATE public.legal_unit SET edit_comment = 'statbus-279 wedge arc' WHERE id = (SELECT MIN(id) FROM public.legal_unit);\" | ./sb psql"

echo ""
echo "── wait for a derive child to be PROCESSING AND BLOCKED on that lock ──"
_blocked=0
for _i in $(seq 1 "$DERIVE_WAIT_S"); do
    _n=$(blocked_derive_count)
    [ "${_n:-0}" -ge 1 ] && { _blocked=1; echo "  ✓ observed $_n derive child(ren) processing and parked on the lock (t+${_i}s)"; break; }
    sleep 1
done
if [ "$_blocked" != "1" ]; then
    echo "✗ no derive child reached 'processing' blocked on the lock within ${DERIVE_WAIT_S}s — ingredient 1 was NOT constructed, so a pass here would prove nothing" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT id, command, state FROM worker.tasks ORDER BY id DESC LIMIT 20;\" | ./sb psql" >&2 || true
    exit 1
fi

echo ""
echo "── stop the worker MID-DERIVE (kill, and keep it down) ──"
# -t 0: SIGTERM immediately followed by SIGKILL, so the worker gets no chance to
# tidy the rows it is holding. `stop` (not `kill`) is what keeps the container
# DOWN afterwards despite `restart: unless-stopped` — see the header.
VM_EXEC bash -c "cd ~/statbus && docker compose stop -t 0 worker 2>&1 | tail -5"
_wstate=$(VM_EXEC bash -c "cd ~/statbus && docker compose ps --status running --format '{{.Service}}' 2>/dev/null | grep -cx worker || true" 2>/dev/null | tr -d ' \r\n' || echo "?")
[ "${_wstate:-1}" = "0" ] || { echo "✗ the worker container is still running after stop -t 0 (count=$_wstate) — it would reclaim the rows outside the window" >&2; exit 1; }
echo "  ✓ worker stopped and staying down"

echo ""
echo "── release the lock (deterministic: remove the release file) ──"
_release_hold
echo "  ✓ release file removed; the holder commits and drops the lock"

echo ""
echo "── ASSERT ingredient 1: abandoned 'processing' rows exist ──"
ABANDONED_BEFORE=$(abandoned_processing_count)
echo "  abandoned 'processing' rows: $ABANDONED_BEFORE"
case "$ABANDONED_BEFORE" in
    ''|*[!0-9]*) echo "✗ could not count abandoned rows (got '$ABANDONED_BEFORE')" >&2; exit 1 ;;
esac
[ "$ABANDONED_BEFORE" -ge 1 ] || { echo "✗ no abandoned 'processing' rows after stopping the worker mid-derive — the wedge state was NOT constructed, so anything that follows proves nothing" >&2; exit 1; }
echo "  ✓ the wedge state exists: $ABANDONED_BEFORE row(s) in 'processing' with no live claimant"

# ══════════════════════════════════════════════════════════════════════════
# INGREDIENT (2): the upgrade — a worker restarts INSIDE the read-only window
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "── register B (daemon up) ──"
VM_EXEC bash -c "cd ~/statbus && git fetch origin $B_BRANCH && git cat-file -e $B_FULL"
VM_EXEC bash -c "cd ~/statbus && ./sb upgrade register $B_FULL 2>&1 | tail -20"
wait_for_upgrade_candidate_ready "$VM_NAME" "$B_FULL" "$TICK_WAIT_S"

arc_schedule_daemon_down "$B_FULL"

echo ""
echo "── dispatch the upgrade (./sb install inline-dispatches the scheduled row) ──"
DISPATCH_RC=0
DISPATCH_OUT=$(VM_EXEC bash -c "cd ~/statbus && STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf 2>&1") || DISPATCH_RC=$?
echo "$DISPATCH_OUT" | tail -40
echo "  dispatch ./sb install exit: $DISPATCH_RC"

# ══════════════════════════════════════════════════════════════════════════
# THE ASSERTIONS — what separates a fixed binary from a wedged one
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "── ASSERT the upgrade landed ──"
FINAL_STATE=$(upgrade_state)
echo "  final upgrade row state: $FINAL_STATE"
[ "$FINAL_STATE" = "completed" ] || { echo "✗ B reached '$FINAL_STATE', expected 'completed'" >&2; exit 1; }
echo "  ✓ state='completed'"

echo ""
echo "── ASSERT the wedge did NOT form: the restarted worker reclaimed the rows ──"
# THE LOAD-BEARING ASSERTION. On a pre-265 binary the startup reset is refused
# inside the read-only window, the pre-264 code logs the error and carries on,
# and these rows stay 'processing' forever behind a worker that looks healthy —
# which is precisely the Norway wedge. The count must be zero.
ABANDONED_AFTER=$(abandoned_processing_count)
echo "  abandoned 'processing' rows after the upgrade: $ABANDONED_AFTER"
case "$ABANDONED_AFTER" in
    ''|*[!0-9]*) echo "✗ could not count abandoned rows after the upgrade (got '$ABANDONED_AFTER')" >&2; exit 1 ;;
esac
[ "$ABANDONED_AFTER" -eq 0 ] || {
    echo "✗ THE WEDGE FORMED: $ABANDONED_AFTER row(s) are still 'processing' with no live claimant after the upgrade." >&2
    echo "  The worker restarted inside the read-only window and its startup reset did not reclaim them." >&2
    echo "  This is the STATBUS-262 Norway wedge — 264's retry and 265's exemption are what prevent it." >&2
    exit 1
}
echo "  ✓ zero abandoned rows — the startup reset ran inside the read-only window and reclaimed them"

echo ""
echo "── ASSERT the worker is healthy, not crash-looping ──"
# The OTHER pre-fix shape: with 264's retry but WITHOUT 265's exemption, the
# reset is refused for the whole 5-minute budget and the worker exits FATAL,
# which `restart: unless-stopped` turns into a visible crash-loop. A bounded
# restart count is what separates that from a healthy start.
_wrun=$(VM_EXEC bash -c "cd ~/statbus && docker compose ps --status running --format '{{.Service}}' 2>/dev/null | grep -cx worker || true" 2>/dev/null | tr -d ' \r\n' || echo "0")
[ "${_wrun:-0}" -ge 1 ] || { echo "✗ the worker container is not running after the upgrade" >&2; exit 1; }
_wrestarts=$(VM_EXEC bash -c "cd ~/statbus && docker inspect --format '{{.RestartCount}}' \$(docker compose ps -q worker 2>/dev/null) 2>/dev/null" | tr -d ' \r\n' || echo "?")
echo "  worker container running; RestartCount=$_wrestarts"
case "$_wrestarts" in
    ''|*[!0-9]*) echo "  (could not read RestartCount — reported, not fatal)" ;;
    *) [ "$_wrestarts" -le 2 ] || { echo "✗ worker RestartCount=$_wrestarts — a crash-loop, the 264-without-265 shape (reset refused for the whole budget, then FATAL exit)" >&2; exit 1; } ;;
esac
echo "  ✓ worker healthy"

echo ""
echo "── ASSERT the box is otherwise intact ──"
assert_flag_file_absent "$VM_NAME"
assert_health_passes "$VM_NAME"
assert_demo_data_present "$VM_NAME"

echo ""
echo "PASS: worker-wedge-mid-derive (derive children abandoned mid-flight by a stopped worker; the upgrade restarted the worker INSIDE the read-only window; the startup reset reclaimed every abandoned row, the worker did not crash-loop, and the wedge did not form)"
