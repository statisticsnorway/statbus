---
id: STATBUS-180
title: >-
  daemon-restart-race: crash-recovery restarts the upgrade daemon while the same
  dispatch's restore re-attempt tears down the DB
status: To Do
assignee: []
created_date: '2026-07-14 13:05'
labels:
  - upgrade
  - install-recovery
  - timing
  - low-severity
dependencies: []
priority: low
ordinal: 181000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: no product actor briefly fails by design — two independent actors inside one `./sb install` dispatch should not race each other's containers.
> FOUND: 2026-07-14, restore-broke-reattempt arc run 29325230294 (mechanic diagnosis, log-grounded): runCrashRecovery (install_upgrade.go ~:506) explicitly `systemctl --user start`s the quiesced upgrade daemon right after the pair-terminal write lands — in the SAME window where the SAME dispatch's re-attempt (StateRestoreReattemptable) is stopping/restoring the DB containers. The freshly-started daemon's boot-migrate check hits the DB mid-teardown, fails ("query applied migrations: exit status 2" / "boot migrate up: exit status 1"), unit exits 1, systemd Restart=always retries 30s later and comes up clean (restore complete by then).
> SEVERITY: benign and self-healing (one restart-counter tick, no data effect, no wedge) — but it is a real timing window between two independent product actors, and it costs an NRestarts tick + a FAILURE line in the journal that an operator/diagnostic tool could misread.

CANDIDATE FIX (mechanic's suggestion, unruled): delay the crash-recovery daemon restart until after any same-dispatch re-attempt concludes — i.e. the dispatch's terminal actions ordering becomes: pair-terminal write → re-detect → (re-attempt if matched) → THEN daemon start. Needs an architect look at whether the daemon start has other dependents expecting it earlier.

EVIDENCE: run 29325230294 log 10:41:23 window; the arc's NRestarts bound (2) deliberately tolerates the tick, with a comment pointing here.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect rules the fix shape (reorder daemon start vs re-attempt, or accept-and-document)
- [ ] #2 If reordered: the restore-broke-reattempt arc's NRestarts bound tightens back and the journal shows no FAILURE line in the window — proven by the arc run
- [ ] #3 If accepted: the window is documented at runCrashRecovery's start call with a pointer to this ticket
<!-- AC:END -->
