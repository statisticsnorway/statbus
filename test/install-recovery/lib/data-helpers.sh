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
        # Separate transport RC (gzip-t pattern).  `|| echo "?"` fed "?" on SSH
        # blips; "?" != "0" so the loop never broke and the post-loop check
        # reported a false "timeout".  Capture the pipeline RC instead; skip
        # this iteration on transport failure rather than treating it as data.
        local _poll_rc=0
        non_terminal=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.import_job WHERE state NOT IN ('finished','failed');\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ') || _poll_rc=$?
        if [ "$_poll_rc" -ne 0 ]; then
            echo "  ⚠ import_job poll SSH failed (VM_EXEC rc=$_poll_rc) — skipping iteration" >&2
            sleep "$poll_s"
            elapsed=$((elapsed + poll_s))
            continue
        fi
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
    # Separate transport RC (gzip-t pattern).  `|| echo "?"` fed failed="?" on
    # SSH blips, causing `[ "?" != "0" ]` to fire a false "? import_job row(s)
    # failed" defect claim.  Use elif so the defect assertion only fires when
    # the SSH transport succeeded AND the data shows a real failure.
    local _failed_rc=0
    local failed
    failed=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT count(*) FROM public.import_job WHERE state = 'failed';\" | ./sb psql -t -A" 2>/dev/null | tr -d ' ') || _failed_rc=$?
    if [ "$_failed_rc" -ne 0 ]; then
        echo "  ⚠ could not query failed import_job count (VM_EXEC rc=$_failed_rc) — INFRA error; skipping failed-row check" >&2
    elif [ "$failed" != "0" ]; then
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
    # call happens. The first Hetzner run of scenario 5-install-seed-on-populated caught this
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
    # BASH-3.2 TRAP (macOS /bin/bash, which runs this harness locally): inside
    # $( ... << HEREDOC ... ), the 3.2 parser naively counts single quotes in
    # the heredoc BODY while scanning for the closing paren. An UNPAIRED
    # apostrophe in a comment (e.g. a contraction like are+not written the
    # short way) breaks the parse with a misleading "unexpected token )" at
    # the substitution's end — run r11 burned a VM on exactly this. Keep the
    # heredoc's single-quote count EVEN: no contractions in SQL comments;
    # quoted literals like 'ready' are fine because they pair.
    local upsert_sql
    upsert_sql=$(cat << SQL
WITH input(commit_sha) AS (VALUES ('${head_sha}'))
INSERT INTO public.upgrade
  (commit_sha, committed_at, commit_tags, release_status, summary,
   has_migrations, commit_version, state, scheduled_at,
   started_at, completed_at, rolled_back_at, error,
   log_relative_file_path, skipped_at, dismissed_at, superseded_at,
   docker_images_status, release_builds_status)
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
  'harness-' || substring(input.commit_sha for 8) || '.log', NULL, NULL, NULL,
  'ready'::public.docker_images_status_type,
  'ready'::public.release_builds_status_type
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
  log_relative_file_path = EXCLUDED.log_relative_file_path,
  -- STATBUS-046 claim gate (commit 886c79293) refuses to claim scheduled rows
  -- with docker_images_status='building' (the column default). Fabricated
  -- rows bypass discover()/verifyArtifacts — the only path that would
  -- otherwise flip 'building' to 'ready' — so this helper must declare
  -- 'ready' explicitly. Legitimate, not a gate bypass: the harness has just
  -- installed the target commit from the very per-commit-image registry
  -- verifyArtifacts would have checked, so the images ARE actually present.
  docker_images_status = 'ready'::public.docker_images_status_type,
  -- Same rationale as docker_images_status, other half of the two-level
  -- artifact-readiness check verifyArtifacts owns (fabrication bypasses the
  -- prober that would otherwise flip this too): for commit-channel targets,
  -- release artifacts are not used at all, so 'ready' is the honest declared
  -- state, not just a gate-satisfying default.
  release_builds_status = 'ready'::public.release_builds_status_type
RETURNING id, commit_sha, state, scheduled_at;
SQL
)

    # CLAUDE.md: never echo SQL over SSH — quoting collapses multiline SQL.
    # Write to a local tmp file, scp to VM, pipe via file redirect.
    local sql_file
    sql_file=$(mktemp /tmp/harness-fabricate-XXXXXX.sql)
    printf '%s\n' "$upsert_sql" > "$sql_file"
    chmod 644 "$sql_file"  # mktemp creates mode 600; statbus user needs read access
    scp -O "${SSH_OPTS[@]}" "$sql_file" root@"$VM_IP":/tmp/harness-fabricate.sql
    rm -f "$sql_file"

    # Capture output + exit code separately.
    # The `|| echo "FAILED"` pattern would conflate a successful psql run
    # that emits a WARN (e.g. sb's freshness check on a depth-1 clone) with
    # an actual SSH/psql failure — any WARN containing "failed" would trigger
    # the grep below even though the INSERT succeeded. Instead: check the
    # exit code directly; treat non-zero SSH exit as the failure signal.
    local result ssh_rc=0
    result=$(ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb config generate && ./sb psql -t -A < /tmp/harness-fabricate.sql' && rm -f /tmp/harness-fabricate.sql" \
        2>&1) || ssh_rc=$?
    if [ $ssh_rc -ne 0 ]; then
        echo "✗ fabricate_scheduled_upgrade_row psql failed (rc=$ssh_rc): $result" >&2
        return 1
    fi
    echo "  ✓ row fabricated/transitioned: $result"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────
# fabricate_resume_state <vm_name> <commit_sha> [dead_pid]
#
# STATBUS-044 comment #6 (architect, King-approved 2026-07-04): fabricates
# the RESUME state DIRECTLY — an in_progress public.upgrade row + a
# service-held FORWARD recovery flag (Phase=new-sb-swapped, per the architect's
# explicit reminder — either phase is safe with the F1 parked-skip fix, but
# new-sb-swapped keeps the assertion surface identical to comment #1's spec) with
# (STATBUS-164 half #2: fabrication writes the CANONICAL slug the current product
# stamps; the pre-rename "post_swap" spelling is now a legacy decode-alias only)
# a DEAD pid. There is NO dispatch and NO claim gate involved — unlike
# fabricate_scheduled_upgrade_row (state='scheduled', requires a LIVE daemon
# to claim + dispatch it), this writes the row and the flag file straight to
# disk/DB so the very NEXT service boot's RecoveryBudgetGuard/recoverFromFlag
# discovers them exactly as it would a real crash-resume — the mechanism
# this scenario drives lives entirely in that discovery, not in dispatch.
#
# "Dead PID" is diagnostic-only (UpgradeFlag's own doc comment, service.go):
# the REAL mutex is the kernel flock, which nobody holds since this function
# never opens/locks the file — it just writes JSON. RecoveryBudgetGuard's own
# acquireFlock call (on the next boot) succeeds immediately, exactly as it
# would after a real process death released the flock on fd-close. The PID
# value only needs to be implausible as a real process, never live-checked.
#
# CommitSHA == commit_sha (the caller's current HEAD) so Service.Run's
# recovery-boot checkout (`git checkout flag.CommitSHA`) is a no-op — the
# working tree must already be checked out to commit_sha before calling this
# (mirrors 0-happy-upgrade.sh:118's fetch+checkout-HEAD stage; see the caller
# in 3-postswap-rune-wedge.sh — the sole surviving fabricate_resume_state caller
# after 3-postswap-resume-died-parked was retired, STATBUS-071).
#
# Row shape mirrors fabricate_scheduled_upgrade_row's field list but with
# state='in_progress' directly — chk_upgrade_state_attributes' in_progress
# arm requires scheduled_at + started_at NOT NULL, completed_at +
# rolled_back_at NULL (verified against migration
# 20260424160235_commit_canonical_naming.up.sql). recovery_attempts /
# recovery_parked_at / recovery_parked_reason are left at column defaults
# (0 / NULL / NULL) on INSERT; explicitly reset on the ON CONFLICT UPDATE arm
# so a re-run against a leftover row from an earlier attempt starts clean.
#
# Prints the fabricated row id on stdout (trailing echo) so the caller can
# capture it if needed; returns 0 on success, non-zero on any SQL/transport
# failure.
# ─────────────────────────────────────────────────────────────────────────
fabricate_resume_state() {
    local vm_name="$1" commit_sha="$2" dead_pid="${3:-999999}"

    if [ -z "$commit_sha" ]; then
        echo "  ✗ fabricate_resume_state: commit_sha is required" >&2
        return 1
    fi

    echo "  [data] fabricating in_progress row + service-held new-sb-swapped flag (dead pid=$dead_pid) for $commit_sha"

    # Same BASH-3.2 quote-parity trap as fabricate_scheduled_upgrade_row's
    # heredoc above: keep the single-quote count in this heredoc EVEN.
    local upsert_sql
    upsert_sql=$(cat << SQL
WITH input(commit_sha) AS (VALUES ('${commit_sha}'))
INSERT INTO public.upgrade
  (commit_sha, committed_at, commit_tags, release_status, summary,
   has_migrations, commit_version, state, scheduled_at, started_at,
   completed_at, rolled_back_at, error,
   log_relative_file_path, skipped_at, dismissed_at, superseded_at,
   docker_images_status, release_builds_status)
SELECT
  input.commit_sha,
  now(),
  '{}'::text[],
  'commit'::public.release_status_type,
  'harness fabricate_resume_state (STATBUS-044 comment #6 boot-migrate park scenario)',
  false,
  'harness-' || substring(input.commit_sha for 8),
  'in_progress'::public.upgrade_state,
  now(),
  now(),
  NULL, NULL, NULL,
  'harness-' || substring(input.commit_sha for 8) || '.log', NULL, NULL, NULL,
  'ready'::public.docker_images_status_type,
  'ready'::public.release_builds_status_type
FROM input
ON CONFLICT (commit_sha) DO UPDATE SET
  state                  = 'in_progress'::public.upgrade_state,
  scheduled_at            = now(),
  started_at              = now(),
  completed_at            = NULL,
  rolled_back_at          = NULL,
  error                   = NULL,
  skipped_at              = NULL,
  dismissed_at            = NULL,
  superseded_at           = NULL,
  recovery_attempts       = 0,
  recovery_parked_at      = NULL,
  recovery_parked_reason  = NULL,
  docker_images_status    = 'ready'::public.docker_images_status_type,
  release_builds_status   = 'ready'::public.release_builds_status_type
RETURNING id;
SQL
)

    local sql_file
    sql_file=$(mktemp /tmp/harness-fabricate-resume-XXXXXX.sql)
    printf '%s\n' "$upsert_sql" > "$sql_file"
    chmod 644 "$sql_file"
    scp -O "${SSH_OPTS[@]}" "$sql_file" root@"$VM_IP":/tmp/harness-fabricate-resume.sql >/dev/null
    rm -f "$sql_file"

    # -q is load-bearing next to -t -A: psql prints the "INSERT 0 1" command
    # tag even in tuples-only mode (r16: parser got '11INSERT01'); only QUIET
    # suppresses command tags, leaving RETURNING's bare id as the sole output.
    local row_id ssh_rc=0
    row_id=$(ssh "${SSH_OPTS[@]}" root@"$VM_IP" \
        "sudo -i -u statbus bash -c 'cd ~/statbus && ./sb config generate >/dev/null && ./sb psql -q -t -A < /tmp/harness-fabricate-resume.sql' && rm -f /tmp/harness-fabricate-resume.sql" \
        2>&1) || ssh_rc=$?
    if [ "$ssh_rc" -ne 0 ]; then
        echo "✗ fabricate_resume_state: row upsert failed (rc=$ssh_rc): $row_id" >&2
        return 1
    fi
    row_id=$(echo "$row_id" | tr -d ' \r\n')
    if ! [[ "$row_id" =~ ^[0-9]+$ ]]; then
        echo "✗ fabricate_resume_state: could not parse row id from psql output: '$row_id'" >&2
        return 1
    fi
    echo "  ✓ row fabricated: id=$row_id state=in_progress"

    # Flag JSON, single-line (no embedded single quotes anywhere in the
    # value — safe to pass through VM_EXEC's printf-%q transport, same
    # nested-quote pattern the scenario already uses for the UPGRADE_CALLBACK
    # marker line). Step/PriorDeathStep omitted (empty — a fresh flag that
    # has never recorded a death, matching a genuine first-time crash).
    local started_at_utc flag_json
    started_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    flag_json="{\"id\":${row_id},\"commit_sha\":\"${commit_sha}\",\"pid\":${dead_pid},\"started_at\":\"${started_at_utc}\",\"invoked_by\":\"harness-fabricate-resume-state\",\"trigger\":\"recovery\",\"holder\":\"service\",\"phase\":\"new-sb-swapped\"}"

    if ! VM_EXEC bash -c "cd ~/statbus && mkdir -p tmp && printf '%s\n' '$flag_json' > tmp/upgrade-in-progress.json"; then
        echo "✗ fabricate_resume_state: could not write tmp/upgrade-in-progress.json" >&2
        return 1
    fi
    VM_EXEC bash -c "grep -q '\"phase\": *\"new-sb-swapped\"' ~/statbus/tmp/upgrade-in-progress.json" || {
        echo "✗ fabricate_resume_state: flag file did not land as expected" >&2
        VM_EXEC bash -c "cat ~/statbus/tmp/upgrade-in-progress.json" >&2 || true
        return 1
    }
    echo "  ✓ flag fabricated: tmp/upgrade-in-progress.json (holder=service phase=new-sb-swapped pid=$dead_pid)"
    echo "$row_id"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────
# wait_for_upgrade_candidate_ready <vm_name> <commit_sha> [budget_s]
#
# Polls public.upgrade until the candidate row for commit_sha reports
# docker_images_status='ready' — i.e. the service's verifyArtifacts (service.go:1101)
# confirmed the four per-commit SERVICE images (db/app/worker/proxy:<commit_short>)
# the upgrade pipeline pulls. `./sb upgrade register` pokes the service (NOTIFY
# upgrade_check → discover → verifyArtifacts) which flips 'building'→'ready' once
# the registry manifests exist (the CI image-wait gate guarantees they do). This
# is the spec's "verifyArtifacts status" readiness — NOT release_builds_status,
# which tracks GitHub RELEASE artifacts (binary self-update) that need not exist
# for a fresh commit/rc and would spuriously time out. Gates the criterion-8
# happy-path real-path proof's `./sb upgrade schedule` on register→ready
# (STATBUS-086). Bounded; returns non-zero on timeout (prints the last-seen status).
# ─────────────────────────────────────────────────────────────────────────
wait_for_upgrade_candidate_ready() {
    local vm_name="$1" commit_sha="$2" budget_s="${3:-120}"
    local start status elapsed
    start=$(date +%s)
    echo "  [data] waiting for candidate $commit_sha → docker_images_status='ready' (budget ${budget_s}s)"
    while :; do
        status=$(VM_EXEC bash -c "cd ~/statbus && echo \"SELECT docker_images_status FROM public.upgrade WHERE commit_sha = '$commit_sha' ORDER BY id DESC LIMIT 1;\" | ./sb psql -t -A" 2>/dev/null | tr -d ' \r\n' || echo "?")
        if [ "$status" = "ready" ]; then
            echo "  [data] ✓ candidate images ready"
            return 0
        fi
        elapsed=$(( $(date +%s) - start ))
        if [ "$elapsed" -ge "$budget_s" ]; then
            echo "  ✗ candidate $commit_sha did not reach docker_images_status='ready' within ${budget_s}s (last='$status')" >&2
            return 1
        fi
        sleep 3
    done
}

# ─────────────────────────────────────────────────────────────────────────
# seed_pre_upgrade_snapshot <vm_name>
#
# Seeds a REAL, restorable pre-upgrade-active DB snapshot so a recovery's
# snapshot-restore performs an ACTUAL rollback of the DB volume rather than the
# no-backup no-op (restoreDatabase returns nil when the dir is absent —
# exec.go:698 — which would land a HOLLOW rolled_back on an un-restored DB).
#
# Mirrors the product's backupDatabase (cli/internal/upgrade/exec.go:424):
#   1. stop the db container (quiesce PGDATA for a consistent file-level copy);
#   2. rsync the named PGDATA volume into ~/statbus-backups/pre-upgrade-active
#      (= backupRoot()/backupActiveName, exec.go:244/263 — the exact dir
#      pickLatestBackup returns and restoreDatabase rsyncs back into the volume);
#   3. start the db again and wait for it to accept connections.
#
# Used by the STATBUS-017 reproducer 3-postswap-migrate-killed-after-commit
# (cell c). CALLER ORDERING IS LOAD-BEARING:
# invoke AFTER the in_progress upgrade row is fabricated (so the snapshot
# captures the row — the rollback's terminal `UPDATE ... WHERE id=<row>` must
# find it) but BEFORE the wedge object is created (the orphan table for cell c)
# so the restore REMOVES the wedge object. A snapshot taken
# after the orphan would restore the wedge state and re-trip the next boot.
#
# Returns 0 on success; non-zero on failure.
# ─────────────────────────────────────────────────────────────────────────
seed_pre_upgrade_snapshot() {
    local vm_name="$1"
    echo "  [data] seeding pre-upgrade-active DB snapshot (R2: a real restore source for recoveryRollback)"

    # TRANSPORT: write the body to a local temp file, scp it to /tmp on the VM,
    # `chmod 0644` it (scp -O lands root-owned mode 600 — statbus can't read it
    # otherwise), then run it via `sudo -i -u statbus bash /tmp/seed-snapshot.sh`.
    # This is the gold-standard install-script transport (vm-bootstrap.sh:565-574):
    # bash reads the script from a FILE, so its contents are parsed ON THE VM and
    # NEVER pass through a shell `-c` arg-quoting layer.
    #
    # Do NOT use `VM_EXEC bash -c '<multi-line body>'` here: the printf %q +
    # `sudo -i -u statbus -- bash -c` transport mangled a body that ASSIGNS a var
    # and references it later — run 27239835249 saw $vol/$dest come out EMPTY
    # (`docker run -v "":/source ...`), so the seed failed before recovery ever
    # ran. The heredoc delimiter is QUOTED ('SEEDSCRIPT') so $vol/$dest/$HOME/$(…)
    # are written literally and expand on the VM, not locally.
    local script_file
    script_file=$(mktemp)
    cat > "$script_file" <<'SEEDSCRIPT'
set -euo pipefail
cd ~/statbus
# Discover the PGDATA volume by suffix (dbVolumeName() == COMPOSE_INSTANCE_NAME
# + "-db-data", exec.go:227-231) rather than re-deriving COMPOSE_INSTANCE_NAME.
vol=$(docker volume ls --format '{{.Name}}' | grep -- '-db-data$' | head -1)
if [ -z "$vol" ]; then
    echo "  ✗ seed_pre_upgrade_snapshot: no *-db-data docker volume found" >&2
    exit 1
fi
dest="$HOME/statbus-backups/pre-upgrade-active"
mkdir -p "$dest"
echo "    volume=$vol dest=$dest"
# Quiesce the DB for a consistent file-level copy (mirrors backupDatabase,
# exec.go:424). docker compose resolves the project from ~/statbus/.env (same as
# the green 1-boot-advisory-too-early `docker compose restart db`).
docker compose stop db >/dev/null 2>&1 || true
docker run --rm -v "$vol":/source:ro -v "$dest":/dest alpine \
    sh -c 'apk add --no-cache rsync >/dev/null 2>&1 && rsync -a --delete /source/ /dest/'
docker compose start db >/dev/null 2>&1
# Wait for the DB to accept connections again before the caller resumes SQL.
ok=0
for _ in $(seq 1 30); do
    if ./sb psql -t -A -c 'SELECT 1' >/dev/null 2>&1; then ok=1; break; fi
    sleep 1
done
if [ "$ok" != "1" ]; then
    echo "  ✗ seed_pre_upgrade_snapshot: db did not accept connections after restart" >&2
    exit 1
fi
echo "    snapshot rsync complete; db back up"
SEEDSCRIPT

    scp -O "${SSH_OPTS[@]}" "$script_file" root@"$VM_IP":/tmp/seed-snapshot.sh >/dev/null
    rm -f "$script_file"
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" 'chmod 0644 /tmp/seed-snapshot.sh'
    local rc=0
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" 'sudo -i -u statbus bash /tmp/seed-snapshot.sh' || rc=$?
    ssh "${SSH_OPTS[@]}" root@"$VM_IP" 'rm -f /tmp/seed-snapshot.sh' >/dev/null 2>&1 || true
    if [ "$rc" -ne 0 ]; then
        echo "  ✗ seed_pre_upgrade_snapshot failed (exit $rc)" >&2
        return 1
    fi
    echo "  ✓ pre-upgrade-active snapshot seeded"
    return 0
}
