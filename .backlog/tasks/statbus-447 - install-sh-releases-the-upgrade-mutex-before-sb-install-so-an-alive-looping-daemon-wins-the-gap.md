---
id: STATBUS-447
title: >-
  install.sh hands the upgrade lock to ./sb install without releasing it, so a
  looping old daemon cannot refuse the repair
status: In Progress
assignee: []
created_date: '2026-10-05 10:20'
updated_date: '2026-10-15 20:09'
labels:
  - install
  - upgrade
  - field-report
  - operator-experience
dependencies: []
references:
  - STATBUS-039
  - STATBUS-436
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The official install command always gets its turn: when `install.sh` hands over to `./sb install`, no other party can take the upgrade lock in between, so a looping old daemon cannot refuse the repair meant to replace it.

### Zoom out
`install.sh` takes the upgrade lock, then starts `./sb install`, which takes it again. If the lock is released in that gap, anything polling the lock can win it. A resident old daemon stuck in a fast retry loop holds it most of the time and wins almost every gap, so the official repair is refused.

Owner decision (2026-10-05): **remove the race, do not detect and kill.** A count-based takeover ("more than 5 failures in 5 minutes, so kill the holder") was rejected by simulation: it kills a healthy upgrade that happens to follow a few manual failures, because the count describes the past while the kill hits the present holder. The chosen design is a **gapless handoff**: `install.sh` keeps the open lock descriptor and hands it to `./sb install` across the process boundary, never releasing it. No thresholds, nothing box-specific. The existing takeover of a crash-looping unit (STATBUS-039) stays, since a unit that keeps dying is by definition not progressing.

### Zoom in
- **Incident, demo 2026-10-05 10:17 UTC:** `./cloud.sh install demo` (rc.14) printed `Upgrade mutex acquired; continuing.` and then `An upgrade is already running.` Demo's resident v2026.09.2 daemon was alive and looping on row 25829 (the false STATBUS-436 capture), holding the lock about 1.7 s of every 1.9 s with `NRestarts=0`. Simulation with real flocks at that cadence: `tmp/lock-sim-447/sim3.pl` (case A) and `sim2.pl` (inverse case B).
- **Shipped:** first version on 2026-10-05 (`483824feb`, `cafa33889`, `784ee8a3d`, `7cf1cfe5a`) after an adversarial review blocked unsafe descriptor ownership, then a simpler cleanup on 2026-10-06 (master `cbaff1c5a`, reviewed MERGE in `tmp/447-kiss-review.md` and `tmp/447-existing-marker-review-2.md`). The receiver adopts the inherited descriptor directly, and existing recovery and restart markers reuse the held lock. `cloud.sh` shows the signing-key hint only on a signature failure (`cafa33889`). Regression from the exec continuation fixed as STATBUS-450 (`7e92d1151`).
- **Proof, real flocks:** `test/install-recovery/tests/install-gapless-handoff-test.sh` (in Harness Selftest). Scenario A, an alive looping holder at demo's cadence: one installer run completes, and it fails on the old code. Scenario B, a healthy holder: the installer waits and never kills.
- **Proof, rehearsal:** the STATBUS-436 operator rehearsal passed in a single installer run on rc.15 and again on rc.16 (`tmp/436-operator-rc16.PASS.log`). The old daemon's attempt during install was refused with `another ./sb install is already running`.
- **Proof, demo:** on 2026-10-06 08:29:50 UTC the owner ran `./cloud.sh install demo v2026.10.0-rc.16`. Binary, checkout, resident daemon and containers were rc.16, the v2026.09.3 loop stopped, and `NRestarts` was 0 (recorded on STATBUS-452). The wrong ledger row that install left was STATBUS-452's defect, now Done.

### Closing review
- **Memory:** "remove the race rather than detect and kill; a failure count describes the past, a kill hits the present" is a lesson worth keeping.
- **Documentation:** none needed.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 install.sh hands the held lock to `./sb install` with no release in between, and `./sb install` adopts the inherited descriptor (`install-gapless-handoff-test.sh`)
- [x] #2 Scenario A (an alive looping holder at demo's cadence) completes in one installer run and fails on the old code; scenario B (a healthy holder after manual failures) waits and never kills (`install-gapless-handoff-test.sh`)
- [x] #3 The STATBUS-436 operator rehearsal passes in a single installer run with no retry (rc.15 and rc.16)
- [x] #4 cloud.sh prints the signing-key hint only on a signature-verification failure (`cafa33889`)
- [x] #5 The owner's `./cloud.sh install demo <candidate>` repairs demo in one run: binary, checkout, resident daemon and containers at the candidate, the old loop stopped, `NRestarts` 0 (rc.16, 2026-10-06 08:29:50 UTC, recorded on STATBUS-452)
- [ ] #6 [Owner] Accept the 2026-10-06 rc.16 demo install as AC5's proof without the 10-minute page observation, recorded in Implementation Notes; then set Done
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** `install-gapless-handoff-test.sh` in Harness Selftest; green on master `cbaff1c5a` (CI `37469525031` among six workflows, 2026-10-06); re-run locally 2026-10-15, both scenarios pass.
- **AC3:** `tmp/436-operator-rc15.PASS.log`, `tmp/436-operator-rc16.PASS.log`.
- **AC4:** `cafa33889` (branch commit `805c244ce`).
- **AC5:** STATBUS-452 description, 2026-10-06 entry. The original criterion also asked for observation over at least 10 minutes and "a page loads and stays"; the 452 record covers the daemon and loop, not the 10-minute page check.
- **History:** the full implementation diary (F1 to F7, reviews, worker sessions) is in Git history of this file, last full version at `b0a61de01`.
<!-- SECTION:NOTES:END -->
