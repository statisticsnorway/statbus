---
id: STATBUS-509
title: Keep install completion from scheduling another upgrade
status: In Progress
assignee: []
created_date: '2026-10-15 11:16'
updated_date: '2026-10-15 13:13'
labels:
  - upgrade
  - install
dependencies: []
priority: high
ordinal: 435204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A successful install records completion without scheduling another upgrade. Only an operator or the channel schedules work.

### Zoom out
Bookkeeping must not schedule work. Reusing the scheduler to revive an installed version woke a resident daemon, turning a successful install into a failed upgrade. Keep completion inside its own transaction.

### Zoom in
- **Observed:** rc.03 LXD run `38714275075`, `5-install-source-identity-operator`, recorded `v2026.10.1-rc.03` installed (`install_completed`), but its row failed: “Could not acquire upgrade-mutex flag file”.
- **Cause:** `rearmRankingRetiredInstallation` (`cli/cmd/install.go`) called `public.upgrade_schedule`, setting `scheduled_at`. `upgrade_notify_daemon_trigger` emitted `NOTIFY upgrade_apply`. The resident `v2026.09.2` daemon rescheduled the completed row, claimed it, hit the install mutex, and called unguarded `failUpgrade`. The earlier rc.02 pass did not establish safety against this race.
- **Implemented:** `6f7ecb2ea` re-arms only eligible ranking-retired rows: `superseded → available → completed`, retaining the row lock, positive retirement evidence, audited actor and transaction. `scheduled_at` stays NULL: no notification.

### Diagnostic fix
`test/install-recovery/lib/lxd-backend.sh` ran `journalctl --user _UID=1001` as root, returning “No entries”. The same commit reads the system journal by UID and captures `public.upgrade` plus `upgrade_state_log` (actor, application name, backend PID, query).
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
### Evidence
Landed `6f7ecb2ea`, 2026-10-15. Recorded results, not rerun during this cleanup:
- **Red:** `tmp/opt-red.log`, parent code: `Test442PinnedInstallCompletion` fails in `legacy-call` and `legacy-schedule-operator` for notifying its own SHA; seven modes pass.
- **Green:** `tmp/opt-green.log`: all nine modes pass. Test: `cli/cmd/install_442_completion_test.go`. pg_regress 131 expects `superseded → available → completed`, NULL `scheduled_at`, both transitions attributed to the install actor.
- **Broader checks:** `./dev.sh test-livedb` exit 0 (upgrade, install, livedocker); `go test ./internal/...` 22 packages pass; `go test ./cmd` passes; `golangci-lint` zero issues. STATBUS-242 rewind audit: new write classified success-path-only (Count 2), with reason.
- **Observer pitfall:** pgx `ConnConfig` copies `OnNotification`. Clear the copied hook so the listener sees notifications; the initial run falsely passed without this correction.

### Closing review
AC4 remains open. Before marking Done, record decisions on:
- **Memory:** should the observer lesson be retained?
- **Documentation:** does the bookkeeping/scheduling boundary need permanent guidance?
- **Cleanup:** resolve or link an owned follow-up for untiered `cli/cmd` livedb tests (442, 452kiss), requiring an owned DSN. The recorded 442 run used `statbus_442_overnight_1006`, recreated from current `statbus_seed`.
Record “none needed” where appropriate, plus any other required cleanup.

### Closing review answers (2026-10-15)
- **Memory:** yes, stored: a pgx `ConnConfig` copy keeps `OnNotification`; clear it on a LISTEN observer or it sees nothing.
- **Documentation:** yes. The boundary is now stated where it is enforced: the comment in `rearmRankingRetiredInstallation` and pg_regress 131. Proposed for doc/upgrade-recovery-model.md: "install bookkeeping never sets scheduled_at" (awaiting owner choice).
- **Cleanup:** `cli/cmd` livedb tests (442, 452kiss) are in no tier; needs a follow-up ticket (owner to confirm before I file it).

### Closing review, corrected (owner review 2026-10-15)
- **Documentation:** the earlier "install bookkeeping never sets scheduled_at" proposal was withdrawn: a prohibition in an unrelated doc is never found from the definition. Instead `cd3b6ada8` defines the meaning on the columns: `scheduled_at` is a request for the daemon to run a version, `completed_at` records an outcome (`COMMENT ON COLUMN`, migration `20261015131116`, doc/db regenerated). The install's re-arm comment and both tests now point to the column. AGENTS.md gained the general rule (`4ec000714`).
- **Verification:** pg_regress 131 ok; Test442PinnedInstallCompletion ok (all modes) on a database cloned from the current seed; cli builds and vets.
<!-- SECTION:NOTES:END -->
