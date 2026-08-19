---
id: STATBUS-241
title: >-
  abort-restore-loses-backup-path: the ABORT branch's volume rewind erases the
  recorded backup_path and no terminal write re-imposes it — the abort-hold
  guard fails open by a second route
status: To Do
assignee: []
created_date: '2026-08-19 00:16'
labels:
  - upgrade-recovery
  - release
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - '.backlog/completed/statbus-228 (comments #15+)'
priority: high
type: bug
ordinal: 234000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A box whose upgrade aborts on the git-corrupt route is supposed to keep a read-only hold on its broken volume until a human replays the retained backup — but the abort path itself erases the row's record of that backup, so the hold's guard reads zero and releases early on exactly the population it protects. This is STATBUS-228 Defect 1's fail-open reached by a second route, found by prediction during the rc.05 arc corrections, before any fleet observed it.

WHAT THE EVIDENCE SHOWS (engineer, STATBUS-228 comment #15, verified at source): the ABORT branch calls restoreDatabase (service.go:8609) BEFORE its terminal write. That restore rewinds the database volume — and with it public.upgrade — to the pre-upgrade snapshot, taken BEFORE the post-reconnect recorder ran, where backup_path is NULL. NONE of the four writeRollbackTerminal call sites re-impose backup_path (:2971, :8302, :8332, :8704 — they impose only state/error/recovery_attempts). The mechanism is proven, not theorized: it is exactly why recovery_attempts needs explicit re-imposition (STATBUS-181), demonstrated live at rc.03 where the counter stuck at 1.

CONSEQUENCE: the abort-hold guard (service.go:3841, SELECT COUNT(*) ... state='failed' AND backup_path IS NOT NULL) reads zero, and the read-only hold protecting the broken volume is stripped early. STATBUS-111's human-gated replay also cannot see the row.

PREDICTED OBSERVABLE: restore-broke-reattempt-arc.sh:480 — newly reachable after the rc.06 arc corrections — asserts a non-null backup_path on this route and is PREDICTED TO FAIL. That red, if it appears, is a PRODUCT finding confirming this ticket, never a stale assertion; the arc's failure message says so in place (escalate, don't edit).

THE FIX SHAPE (architect rules): re-impose backup_path in the terminal write after the volume rewind, the same pattern STATBUS-181 established for recovery_attempts — the flag carries the identity across the rewind, so the value exists to re-impose. Whether this lands before the rc.06 cut or the cut deliberately measures the prediction first is the architect's fork, ruled on STATBUS-228.

WHAT IS ACHIEVED: the read-only hold on a broken volume holds for as long as the replay it gates remains undone — by mechanism, on both routes that can erase the record.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect rules the fix shape and the sequencing (fix before rc.06 vs cut-and-measure the prediction)
- [ ] #2 backup_path survives the ABORT-route volume rewind onto the terminal row, with a RED-first oracle at the unit level
- [ ] #3 restore-broke-reattempt phase (ii)'s :480 assertion observed GREEN at a suite run — the 228 recorder's evidence finally executes
<!-- AC:END -->
