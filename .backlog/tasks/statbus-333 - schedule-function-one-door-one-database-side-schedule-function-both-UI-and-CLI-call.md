---
id: STATBUS-333
title: >-
  schedule-function-one-door: one database-side schedule function both UI and
  CLI call
status: To Do
assignee: []
created_date: '2026-09-01 09:46'
updated_date: '2026-09-01 12:22'
labels: []
dependencies: []
priority: high
type: enhancement
ordinal: 326000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Issue: scheduling a candidate is written differently per door. The CLI resets the full lifecycle and supersedes older candidates (promoteExistingCandidate, cli/internal/upgrade/service.go:5180; supersede at :5168); the UI PATCHes only {state,scheduled_at} (app/src/app/admin/upgrades/page.tsx:746). So a UI schedule cannot retry a ran/failed row, cannot un-park, never supersedes — and any same-commit retry (one row per commit: UNIQUE commit_sha) erases the failure evidence.

Fix — KING-APPROVED DESIGN 2026-09-01, full text in .backlog/docs/statbus-333-design.md (execute THAT document; this description is the summary):
ONE database function `public.upgrade_schedule(p_commit_sha text, p_recreate boolean DEFAULT false) RETURNS TABLE (schedule_result text, upgrade_id integer, landed_state public.upgrade_state, superseded_count integer)`, SECURITY INVOKER (DEFINER would break STATBUS-317 actor attribution), EXECUTE revoked from PUBLIC, granted to admin_user. Both doors call it: UI via PostgREST RPC, CLI/service replace their raw UPDATEs (promoteExistingCandidate AND scheduleStep). One transaction: lock row FOR UPDATE → 'unregistered' if absent → 'in_progress' if live and not parked → 'restore_reattempt_required' if failed AND backup_path IS NOT NULL (human-gated via ./sb install, now DB-enforced) → 'already_scheduled' no-op on target → else supersede-older FIRST via existing public.upgrade_supersede_older (frees the upgrade_single_scheduled singleton; do not duplicate its SQL) → full reset (started/completed/error/rolled_back/skipped/dismissed/superseded/log-path all NULL, recreate set, un-park + recovery budget zeroed, AND backup_path NULL — today uncleared, a stale pointer misclassifies a retried-then-failed row as restore-broke, state.go:250) → RETURNING actual landed state ('superseded' if the obsolete-pending trigger rewrote it).

Evidence preservation (the King's minimal mechanism, no new table): five nullable columns on existing append-only upgrade_state_log — old_error, old_log_relative_file_path, old_backup_path, old_recovery_parked_reason, old_recovery_attempts — snapshotted from OLD by the existing AFTER UPDATE capture trigger (widen INSERT/VALUES only; predicate unchanged; \sf-dump the trigger fn per AGENTS.md after migrating local DB to HEAD). Every reset path changes state or park marker, so OLD archives the evidence before the NULLing. Accepted trade-off: transition-grained history; error by value, narrative by file pointer. No backfill of historical log rows.

Required companions in the same change: (a) exclusive log-file creation — second-resolution name + os.Create truncates on same-second retry (progress.go:103-141); O_CREATE|O_EXCL with numeric suffix on EEXIST; crash-recovery append path stays one file; (b) UI: add recovery fields to the Upgrade interface, render Parked (today parked shows as "Upgrading", page.tsx:1311), Retry button on failed(backup NULL)/rolled_back/parked cards calling the one RPC, restore-broke shows ./sb install guidance, only scheduled/already_scheduled redirect to maintenance; (c) onApplyScheduled drops its Go-side supersede; RunSchedule drops its late supersede; update the upgrade.go:228 tripwire comment to name the function; ./sb types generate; (d) STATBUS-159 claim-time displacement stays at claim — NOT in this function; (e) already_scheduled is a strict no-op (clean break from RunSchedule's repoke of scheduled_at/recreate — unschedule+schedule to change intent).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 pg_regress (extend test/sql/327_test_upgrade_procedures.sql, actor fixtures per 128): failed row (backup NULL) rescheduled as test.admin → schedule_result='scheduled', superseded_count=1; row clean (all lifecycle+evidence+recovery fields NULL/zero, new scheduled_at); newest state_log row carries old_state='failed', old_error, old_log_relative_file_path, old_recovery_attempts, actor_source='verified'; older available candidate superseded
- [ ] #2 pg_regress: parked in_progress row rescheduled → lands scheduled + clean, log row captures old park time/reason/error/log/backup/budget; UnparkByID-shape (park clears, state stays in_progress) still logs one row with OLD park evidence
- [ ] #3 pg_regress: live in_progress (not parked) → 'in_progress', zero mutation, no log row; failed+backup_path → 'restore_reattempt_required', zero mutation; unregistered SHA → 'unregistered'; already-scheduled → 'already_scheduled' with target untouched; regular user refused at EXECUTE
- [ ] #4 Go: promoteExistingCandidate and scheduleStep contain no raw UPDATE public.upgrade SET state='scheduled' — both call public.upgrade_schedule; source-audit/terminal_rewind_audit tests updated; scheduleResult mapping covers all six results
- [ ] #5 Go unit test: two NewUpgradeLog calls with identical id/version/startTime produce distinct paths and the first file's contents survive
- [ ] #6 UI: Retry on failed(backup NULL)/rolled_back/parked cards and Schedule on available all call the upgrade_schedule RPC; parked renders as Parked; restore-broke card shows ./sb install guidance with no retry; only scheduled/already_scheduled redirect to maintenance; database.types.ts regenerated
- [ ] #7 Migration follows AGENTS.md: \sf dump of upgrade_state_log_capture taken from a HEAD-migrated local DB (no 2>&1), down migration restores the exact pre-change trigger BEFORE dropping the five columns; ./dev.sh test fast green
<!-- AC:END -->
