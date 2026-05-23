#!/bin/bash
# data-helpers.sh — primitives that populate a freshly-installed VM with
# realistic data so failure-injection scenarios have something non-trivial
# to lose. Anchors the R5 catastrophic-loss detector + the R1 worker-
# contention path.
#
# The canonical population path is the demo dataset that ships in
# samples/demo/. Scenarios MUST NOT invent ad-hoc test data — drift
# between the harness dataset and the demo dataset is a maintenance
# trap. If a scenario needs richer data, extend samples/demo/, not the
# harness.
#
# Source order:
#   source lib/vm-bootstrap.sh    # for VM_EXEC + HARNESS_ROOT
#   source lib/data-helpers.sh
#   source lib/wedge-helpers.sh
#   source lib/assertions.sh

# ─────────────────────────────────────────────────────────────────────────
# populate_with_demo_data <vm_name>
#
# Runs samples/demo/import-demo-data.sh against an installed VM and
# blocks until every queued import_job row reaches a terminal state
# (finished or failed). The demo script enqueues four imports — legal
# units, formal establishments, informal establishments, legal
# relationships — and the worker drives them asynchronously.
#
# Operator-email contract: the demo script verifies a user exists in
# public.user before queueing any work. The harness's bootstrap seeds
# `test@statbus.org` via .users.yml; we use that email rather than
# inventing one. If a scenario provisions a different VM shape, override
# via DEMO_USER_EMAIL.
#
# Failure surfacing: any import_job ending in 'failed' is a real harness
# error (the demo dataset is supposed to be a known-good corpus). We
# emit the failed jobs' slugs + errors and return non-zero so the
# scenario's `set -e` bails.
#
# Timeout: imports usually finish in 30-60 s on a cx23. The poll budget
# defaults to 5 min — generous for slower hardware or under contention.
# Override via DEMO_IMPORT_MAX_WAIT_S.
#
# On success: echoes a single line with the resulting row counts so
# scenario logs document the populated state.
populate_with_demo_data() {
    local vm_name="$1"
    local user_email="${DEMO_USER_EMAIL:-test@statbus.org}"
    local max_wait_s="${DEMO_IMPORT_MAX_WAIT_S:-300}"

    echo "  [data] populating $vm_name with samples/demo dataset (USER_EMAIL=$user_email)"

    # Run the demo importer. The script lives at samples/demo/import-
    # demo-data.sh, which is part of the repo cloned into ~/statbus by
    # install_statbus_in_vm; no scp needed.
    if ! VM_EXEC bash -c "cd ~/statbus && USER_EMAIL='$user_email' bash samples/demo/import-demo-data.sh"; then
        echo "  ✗ import-demo-data.sh exited non-zero" >&2
        return 1
    fi

    # Poll for import_job terminal state. The 'state' column transitions
    # from queued/processing/etc to either 'finished' or 'failed'. We
    # block on count of non-terminal rows reaching 0.
    echo "  [data] waiting for import_job rows to reach terminal state (budget ${max_wait_s}s)"
    local elapsed=0
    local poll_s=5
    local non_terminal
    while [ "$elapsed" -lt "$max_wait_s" ]; do
        non_terminal=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.import_job WHERE state NOT IN ('finished','failed');\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "?")
        if [ "$non_terminal" = "0" ]; then
            break
        fi
        # Periodically surface the in-flight slugs so a stuck import is visible.
        if [ $((elapsed % 30)) -eq 0 ]; then
            local in_flight
            in_flight=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT string_agg(slug || '(' || state || ')', ', ') FROM public.import_job WHERE state NOT IN ('finished','failed');\" | ./sb psql -t -A" 2>/dev/null || echo "?")
            echo "    [data] in-flight (elapsed ${elapsed}s, non_terminal=$non_terminal): $in_flight"
        fi
        sleep "$poll_s"
        elapsed=$((elapsed + poll_s))
    done

    if [ "$non_terminal" != "0" ]; then
        echo "  ✗ import_job rows still non-terminal after ${max_wait_s}s — timeout" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT slug, state FROM public.import_job ORDER BY slug;\" | ./sb psql" >&2 || true
        return 1
    fi

    # Surface any 'failed' import_jobs as a real error — the demo dataset
    # is supposed to be a known-good corpus, so 'failed' means something
    # broke and we shouldn't pretend the scenario has clean baseline data.
    local failed
    failed=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.import_job WHERE state = 'failed';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "?")
    if [ "$failed" != "0" ]; then
        echo "  ✗ $failed import_job row(s) ended in 'failed' state" >&2
        VM_EXEC bash -c "cd ~/statbus && echo \"SELECT slug, state, error FROM public.import_job WHERE state = 'failed';\" | ./sb psql" >&2 || true
        return 1
    fi

    # CRITICAL: wait for the worker queue to fully drain before returning.
    #
    # import_job terminal != worker quiesced. When an import_job
    # finishes, the worker spawns derivation tasks (collect_changes,
    # derive_units_phase, statistical_history_facet_derive, …) that
    # update public.statistical_unit, public.statistical_history, and
    # related derived tables. Those rows grow while the snapshot
    # call happens. The first Hetzner run of scenario 10 caught this
    # exact drift — legal_unit + establishment were stable
    # (user-imported rows), but statistical_unit grew by 55 and
    # statistical_history by 336 between snapshot and post-install
    # check. No way to assert "data unchanged across the failure
    # window" if the baseline is itself moving.
    #
    # Fix: chain through wait_for_worker_quiesce so populate_with_
    # demo_data returns only when worker.tasks is fully drained
    # (no non-terminal rows). Any subsequent snapshot_demo_data_
    # counts call captures a steady-state baseline.
    if ! wait_for_worker_quiesce "$vm_name" "${DEMO_WORKER_QUIESCE_MAX_WAIT_S:-300}"; then
        echo "  ✗ worker queue did not drain after import_job terminal state" >&2
        return 1
    fi

    # Confirm populated and echo a one-line summary for the scenario log.
    local counts
    counts=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT 'statistical_unit=' || (SELECT count(*) FROM public.statistical_unit) || ' legal_unit=' || (SELECT count(*) FROM public.legal_unit) || ' establishment=' || (SELECT count(*) FROM public.establishment);\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r' || echo "?")
    echo "  ✓ demo data populated in ${elapsed}s — $counts"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────
# wait_for_worker_quiesce <vm_name> [max_wait_s]
#
# Polls worker.tasks until no row remains in a non-terminal state
# (`completed`, `failed` are terminal; everything else — pending,
# processing, interrupted, waiting — keeps the queue active).
# Returns 0 once the queue is empty for two consecutive polls (so a
# transient "between tasks" window doesn't cause a false-positive);
# returns 1 after max_wait_s without the queue draining.
#
# Used by populate_with_demo_data to chain past the import_job-
# terminal checkpoint to a worker-fully-drained checkpoint —
# necessary because import_job completion spawns derivation tasks
# (collect_changes → derive_units_phase → statistical_history_
# facet_derive → …) that keep mutating derived tables for tens of
# seconds after the import jobs themselves are 'finished'.
#
# Also callable directly from scenarios that need a stable count
# baseline at a different point in the run (e.g. after a recovery
# install that re-triggered derivation).
#
# Defaults: max_wait_s=300 (5 min), poll_s=5, stable_consecutive=2.
# ─────────────────────────────────────────────────────────────────────────
wait_for_worker_quiesce() {
    local vm_name="$1"
    local max_wait_s="${2:-300}"
    local poll_s=5
    local stable_target=2  # require two consecutive zero-count polls
    local elapsed=0
    local stable_count=0
    local non_terminal

    # Filter: exclude future-scheduled tasks. worker.tasks has a scheduled_at
    # column; rows with scheduled_at > NOW() are recurring maintenance tasks
    # (import_job_cleanup, task_cleanup, etc.) that the worker is correctly
    # waiting to run later. Including them in the quiesce check would hang
    # forever — they're not "active work" we're waiting on, they're scheduled
    # future work that's correct to have pending. Per worker.tasks schema in
    # migrations/20250213100637_create_worker_infrastructure.up.sql:
    #   scheduled_at TIMESTAMPTZ, -- When this task should be processed, if delayed.
    local active_filter="state NOT IN ('completed','failed') AND (scheduled_at IS NULL OR scheduled_at <= NOW())"

    echo "  [data] waiting for worker.tasks queue to drain (budget ${max_wait_s}s, requires ${stable_target} consecutive zero polls; future-scheduled tasks excluded)"
    while [ "$elapsed" -lt "$max_wait_s" ]; do
        non_terminal=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM worker.tasks WHERE ${active_filter};\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ' || echo "?")
        if [ "$non_terminal" = "0" ]; then
            stable_count=$((stable_count + 1))
            if [ "$stable_count" -ge "$stable_target" ]; then
                echo "  ✓ worker.tasks drained (${stable_count} consecutive zero polls, ${elapsed}s elapsed)"
                return 0
            fi
        else
            stable_count=0
            if [ $((elapsed % 30)) -eq 0 ]; then
                local active
                active=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT string_agg(DISTINCT command || '(' || state || ')', ', ') FROM worker.tasks WHERE ${active_filter};\" | ./sb psql -t -A" 2>/dev/null || echo "?")
                echo "    [data] worker active (elapsed ${elapsed}s, non_terminal=$non_terminal): $active"
            fi
        fi
        sleep "$poll_s"
        elapsed=$((elapsed + poll_s))
    done

    echo "  ✗ worker.tasks still non-empty after ${max_wait_s}s — last count=$non_terminal" >&2
    VM_EXEC bash -c "cd ~/statbus && echo \"SELECT command, state, count(*) FROM worker.tasks WHERE ${active_filter} GROUP BY command, state ORDER BY count(*) DESC;\" | ./sb psql" >&2 || true
    return 1
}

# ─────────────────────────────────────────────────────────────────────────
# fabricate_scheduled_upgrade_row <vm_name> <head_sha>
#
# Inserts a row in public.upgrade with state='scheduled' for the given
# commit SHA, satisfying chk_upgrade_state_attributes' scheduled-arm
# (scheduled_at NOT NULL; started_at + completed_at + rolled_back_at
# NULL). Used by harness scenarios that need the supervised systemd
# upgrade-service unit to dispatch an upgrade against HEAD's SHA —
# the unit's `discover` machinery only populates rows for commits
# matching git tags, so HEAD (typically untagged in harness flow)
# never appears as state='available' via the natural path.
#
# Idempotent: if a row already exists for the SHA, transitions it to
# 'scheduled' if it isn't already (and clears the lifecycle timestamps
# that would conflict with the 'scheduled' arm). If a fabricated row
# is already in state='scheduled', returns 0 unchanged.
#
# Field rationale (per discover's INSERT shape in service.go:2579 +
# the create_upgrade_table.up.sql + commit_centric_upgrade_table.up.sql
# schema lineage; verified against chk_upgrade_state_attributes in
# migration 20260424160235_commit_canonical_naming.up.sql):
#
#   commit_sha     — required UNIQUE; the HEAD SHA passed in.
#   committed_at   — required NOT NULL; we use now() (the harness
#                    isn't asserting a specific commit timestamp).
#   commit_tags    — TEXT[] default '{}'; we leave empty (HEAD is
#                    untagged in this codepath by construction).
#   release_status — public.release_status_type, default 'commit';
#                    explicit 'commit' satisfies the discover-style
#                    shape and prevents accidental misclassification.
#   summary        — NOT NULL TEXT; static harness marker so an
#                    operator browsing the table sees the row's
#                    provenance.
#   has_migrations — default FALSE; the upgrade-service's discover
#                    leaves this false too — has_migrations is
#                    determined by manifest at upgrade execution
#                    time, not at discover/fabrication time.
#   commit_version — synthetic harness sentinel. discover normally
#                    sets this to a tag name; we use a placeholder
#                    that doesn't collide with any real release tag
#                    shape so a stray operator query that filters by
#                    release tag won't match.
#   state          — 'scheduled' (the row's purpose; satisfies
#                    chk_upgrade_state_attributes' scheduled arm).
#   scheduled_at   — now() (required by the scheduled arm).
#
# Usage:
#   fabricate_scheduled_upgrade_row "$VM_NAME" "$HEAD_SHA"
#
# Returns 0 on successful insert/update; non-zero on SQL error.
# ─────────────────────────────────────────────────────────────────────────
fabricate_scheduled_upgrade_row() {
    local vm_name="$1"
    local head_sha="$2"

    if [ -z "$head_sha" ]; then
        echo "  ✗ fabricate_scheduled_upgrade_row: head_sha is required" >&2
        return 1
    fi

    echo "  [data] fabricating public.upgrade row for $head_sha (state=scheduled)"

    # Pre-existing row? Transition to 'scheduled' if it isn't already,
    # clearing lifecycle timestamps that would conflict with the
    # scheduled arm. The WHERE clause is intentionally permissive — we
    # accept rows in any state and force-reset them into scheduled,
    # because the helper's contract is "make this row scheduled now";
    # callers expect a deterministic post-condition regardless of
    # whatever prior state the row was in.
    local upsert_sql
    upsert_sql=$(cat << SQL
WITH input(commit_sha) AS (VALUES ('${head_sha}'))
INSERT INTO public.upgrade
  (commit_sha, committed_at, commit_tags, release_status, summary,
   has_migrations, commit_version, state, scheduled_at,
   started_at, completed_at, rolled_back_at, error,
   log_relative_file_path, skipped_at, dismissed_at, superseded_at)
SELECT
  input.commit_sha,
  now(),
  '{}'::text[],
  'commit'::public.release_status_type,
  'harness fabricate_scheduled_upgrade_row',
  false,
  'harness-' || substring(input.commit_sha for 8),
  'scheduled'::public.upgrade_state,
  now(),
  NULL, NULL, NULL, NULL,
  NULL, NULL, NULL, NULL
FROM input
ON CONFLICT (commit_sha) DO UPDATE SET
  state            = 'scheduled'::public.upgrade_state,
  scheduled_at     = now(),
  started_at       = NULL,
  completed_at     = NULL,
  rolled_back_at   = NULL,
  error            = NULL,
  skipped_at       = NULL,
  dismissed_at     = NULL,
  superseded_at    = NULL,
  log_relative_file_path = NULL
RETURNING id, commit_sha, state, scheduled_at;
SQL
)

    local result
    result=$(VM_EXEC bash -c "cd ~/statbus && echo \"$upsert_sql\" | ./sb psql -t -A 2>&1" || echo "FAILED")
    if echo "$result" | grep -qi "error\|FAILED"; then
        echo "  ✗ fabricate_scheduled_upgrade_row failed:" >&2
        echo "$result" >&2
        return 1
    fi
    echo "  ✓ row fabricated/transitioned: $result"
    return 0
}
