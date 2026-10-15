---
id: STATBUS-509
title: >-
  Install completion re-arm sends NOTIFY upgrade_apply, so a resident daemon
  re-runs and fails the version just installed
status: In Progress
assignee: []
created_date: '2026-10-15 11:16'
updated_date: '2026-10-15 11:32'
labels:
  - upgrade
  - install
dependencies: []
priority: high
ordinal: 435204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: a successful install's bookkeeping never tells any daemon to run anything. Only an operator or the channel schedules work.

Defect (rc.03 LXD fleet, run 38714275075, 5-install-source-identity-operator): the operator remedy installed v2026.10.1-rc.03 cleanly ('Recorded installed version v2026.10.1-rc.03', callback install_completed), yet the candidate's own row ended failed: 'Could not acquire upgrade-mutex flag file: another ./sb install is already running (install, invoked_by=install.sh:statbus)'.

Cause: STATBUS-442's rearmRankingRetiredInstallation re-armed the ranking-retired installed row through public.upgrade_schedule. That stamps scheduled_at, and upgrade_notify_daemon_trigger turns it into NOTIFY upgrade_apply for the installed SHA at commit. The still-resident v2026.09.2 daemon received it, called upgrade_schedule on the now-completed row (completed is reschedulable), claimed it, met the install's mutex and its old code ran failUpgrade with no state guard. It contradicts install.go's own stated invariant for this path: install bookkeeping never touches scheduled_at. rc.02 passed the same scenario by timing only.

Fix: re-arm in place superseded -> available (same audited actor, same transaction, same positive retirement evidence under the row lock); the completion upsert then takes it to completed. scheduled_at stays NULL, so no NOTIFY.

Also: the LXD failure capture ran 'journalctl --user _UID=1001' as root, which reads root's user journal and printed 'No entries', so the daemon that failed the row left no trace. It now reads the system journal by UID and dumps public.upgrade plus upgrade_state_log (actor, application_name, backend_pid, query).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test442PinnedInstallCompletion observes upgrade_apply from a separate session and fails if install completion notifies its own installed SHA; recorded RED on the parent code (legacy-call, legacy-schedule-operator)
- [x] #2 With the fix the same test is GREEN in all nine modes; pg_regress 131 expects superseded->available->completed with scheduled_at NULL
- [x] #3 LXD failure capture contains the statbus user's daemon journal and the upgrade rows with their state log
- [ ] #4 The next candidate's LXD fleet passes 5-install-source-identity-operator
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Landed 6f7ecb2ea (2026-10-15).
RED (parent code, tmp/opt-red.log): Test442PinnedInstallCompletion legacy-call and legacy-schedule-operator FAIL, 'install completion sent NOTIFY upgrade_apply for its own installed SHA'; the other seven modes pass. Observer note: a pgx ConnConfig copy carries the source conn's OnNotification hook, so the listener clears it, otherwise it is blind (first run passed falsely for that reason).
GREEN (tmp/opt-green.log): all nine modes pass. pg_regress 131 now expects superseded->available->completed with scheduled_at NULL, both transitions attributed to the install actor.
Shared-code set: ./dev.sh test-livedb exit 0 (upgrade + install + livedocker), go test ./internal/... 22 packages ok, go test ./cmd ok, golangci-lint 0 issues. The STATBUS-242 rewind audit flagged the new write site; dispositioned as success-path-only (Count 2) with reason.
Gap noticed: cli/cmd livedb tests (442, 452kiss) are not in any tier; they need an owned DSN. 442 was run against statbus_442_overnight_1006 recreated from the current statbus_seed.
AC4 waits for the next candidate's LXD fleet.
<!-- SECTION:NOTES:END -->
