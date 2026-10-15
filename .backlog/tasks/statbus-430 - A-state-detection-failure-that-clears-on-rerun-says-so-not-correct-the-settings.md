---
id: STATBUS-430
title: >-
  A state-detection failure tells the operator to rerun, not to correct the
  settings
status: In Progress
assignee: []
created_date: '2026-09-29 08:24'
updated_date: '2026-10-15 19:41'
labels:
  - install
dependencies: []
priority: medium
ordinal: 379200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
When the installer cannot tell what state the box is in, it says so and says to run the same command again, never "correct the settings" when nothing about the settings is wrong.

### Zoom out
A state-detection probe can fail for reasons that have nothing to do with the operator's configuration, for example the database restarting at that moment. The refusal must name that truthfully, give the exact rerun command, and change nothing. Only fixed, trusted sentences may cross from the install log to the terminal (STATBUS-402), so the remedy is printed from known values, not echoed from a log line.

Why the database was restarting is a separate question. The likely cause, an old upgrade service rebooting and recreating the database while an install ran, became its own fix in STATBUS-432.

### Zoom in
- **Incident, Finland replay 2026-09-29 (`tmp/ville-replay-v2026.09.3.md` D4):** attempt 2 on the repaired box failed detection with `FATAL: the database system is shutting down`. The Go side returned `the install state could not be determined safely; nothing was changed. Run the same install command again`, but `install.sh`'s exit-78 fallback printed `Installation cannot start with the current settings. Correct the settings, then run: ...`.
- **Shipped (merge `0ff6a590c`, 2026-09-30, after independent reviews `tmp/review-430-2.md` and `tmp/review-evidence-and-430-final.md`):** `install.sh` has a full-line-anchored allowlist entry for the detection refusal, printing the trusted rerun command and a validated support-bundle path; the other exit-78 members were anchored too (`f18c31b2a`, `355c289b7`, `28a1f543a`, `d62d70574`).
- **Proof:** `TestStateDetectionFailureRerunsRatherThanBlamesSettings` (`cli/cmd/install_detection_test.go`) drives the real Go error through the real `install.sh` branch, with raw-psql and suffix-injection negatives. Green 2026-10-15.
- **The restart:** most likely the v2026.09.2 unit in a restart loop re-executing the swapped binary, whose boot ran `config generate` and `up -d db` without the install lock. The source paths were checked; a correlated trace from the original run is missing. The fix is STATBUS-432, merged as `c893c1f02` (2026-10-01, in v2026.10.1): daemon boot defers while an install holds the box, exiting 76. STATBUS-432 is still marked To Do although its fix is on master.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed.
- **Cleanup:** STATBUS-432's status is stale; it should be vetted next.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 install.sh shows the state-detection rerun remedy from trusted command and path values, not the settings sentence and not an echoed log line
- [ ] #2 The cause of the database restart between attempts is identified, and either prevented or documented as expected with the rerun remedy (prevention is STATBUS-432, merged `c893c1f02`; a correlated trace from the original run is missing)
- [x] #3 A test covers the detection-failure message path (`TestStateDetectionFailureRerunsRatherThanBlamesSettings`)
- [ ] #4 Owner decision: accept STATBUS-432's merged interlock as AC2's prevention without a trace from the original Finland run? Yes closes this ticket.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1, AC3:** merge `0ff6a590c`; test green locally 2026-10-15.
- **AC2:** open pending the owner answer; STATBUS-432 (`c893c1f02`) is in v2026.10.1.
- **History:** the 2026-09-29/30 review notes are in Git history.
<!-- SECTION:NOTES:END -->
