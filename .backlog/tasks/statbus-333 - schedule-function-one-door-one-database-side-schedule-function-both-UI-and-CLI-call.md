---
id: STATBUS-333
title: >-
  schedule-function-one-door: one database-side schedule function both UI and
  CLI call
status: To Do
assignee: []
created_date: '2026-09-01 09:46'
updated_date: '2026-09-01 11:57'
labels: []
dependencies: []
priority: medium
type: enhancement
ordinal: 326000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Issue: scheduling a candidate is written differently per door. The CLI resets the full lifecycle and supersedes older candidates (promoteExistingCandidate, cli/internal/upgrade/service.go:5180; supersede at :5168); the UI PATCHes only {state,scheduled_at} (app/src/app/admin/upgrades/page.tsx:746). So a UI schedule cannot retry a ran/failed row, cannot un-park, never supersedes — and any same-commit retry (one row per commit: UNIQUE commit_sha) erases the failure evidence.

Fix (design: tmp/statbus-333-design.md, architect 2026-09-01, approved direction: minimal log-based):
ONE database function `public.upgrade_schedule(p_commit_sha text, p_recreate boolean) RETURNS (schedule_result, upgrade_id, landed_state, superseded_count)`, SECURITY INVOKER (DEFINER would break STATBUS-317 actor attribution), EXECUTE only to admin_user. Both doors call it: UI via PostgREST RPC, CLI/service replace their raw UPDATEs. In one transaction: lock row → refuse live in_progress / restore-broke (`failed AND backup_path IS NOT NULL` stays human-gated via ./sb install, now enforced in the DB) → supersede-older FIRST (frees the upgrade_single_scheduled singleton) → full reset (incl. un-park, recovery budget, skipped_at/dismissed_at per the upgrade.go:228 tripwire, AND backup_path — today unclear-ed, a stale pointer misclassifies a retried-then-failed row as restore-broke, state.go:250) → return the actual landed state (obsolete-pending trigger may rewrite to superseded).

Evidence preservation (the King's minimal mechanism): five nullable columns on the existing append-only upgrade_state_log — old_error, old_log_relative_file_path, old_backup_path, old_recovery_parked_reason, old_recovery_attempts — snapshotted from OLD by the existing AFTER UPDATE capture trigger (widened INSERT only; predicate unchanged). Every reset path changes state or park marker, so OLD archives "attempt N failed with X, log Y" before the NULLing, automatically. Trade-off accepted: transition-grained history, error by value + log by pointer; no attempt table, no second row.

Required companions: (a) attempt log files are NOT distinct today — second-resolution name + os.Create truncates on same-second retry (progress.go:103-141); switch to O_CREATE|O_EXCL with suffix; (b) UI adds Retry to failed(no-backup)/rolled_back/parked cards, renders Parked (today parked shows as "Upgrading", page.tsx:1311), restore-broke shows ./sb install guidance; (c) STATBUS-159 claim-time displacement stays where it is — NOT in this function.

Acceptance: pg_regress (extend test/sql/327): failed row rescheduled via admin role → result 'scheduled', row clean, old error/log/budget visible in state_log with actor_source='verified', older candidate superseded; parked retry and un-park capture; live in_progress and restore-broke refused with no mutation; regular user refused at EXECUTE. Go: no raw schedule UPDATEs remain; same-second log collision test. UI: all retry doors call the one RPC; superseded/in_progress/restore_reattempt responses do not redirect to maintenance.
<!-- SECTION:DESCRIPTION:END -->
