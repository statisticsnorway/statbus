---
id: STATBUS-075
title: >-
  cut-rc04: the single tracker for what's left before we can cut release
  candidate rc.04
status: In Progress
assignee: []
created_date: '2026-06-17 11:04'
updated_date: '2026-06-17 20:12'
labels:
  - install-recovery
  - rc.04
  - gate
  - release
dependencies:
  - STATBUS-074
  - STATBUS-073
priority: high
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE one place that answers: "what are we waiting on to cut rc.04?"

WHY rc.04 MATTERS: Albania (a standalone StatBus box physically inside Albania, with no SSB remote access — upgrades happen only via a local operator through the web UI) installed v2026.05.2 and CANNOT upgrade, because the upgrade crashes. rc.04 is their first working upgrade target. Same crash that stuck Norway weeks ago.

CUT BAR (King's ruling): the install-recovery harness must reach 100% GREEN — every scenario passes, NO "known-acceptable reds" carve-out.

WHAT WE WERE WAITING ON — 3 fix classes, ALL now landed on master @78e770ac:
1. Freshness-reorder (harness staleness guard) — STATBUS-076, done (7f305f70d).
2. Masked-unit unmask (systemd) — done (e6c85c193).
3. Single-source recovery: remove from_commit_sha (the Albania crash) — STATBUS-077 + the gate-pedagogy fix STATBUS-078, done.

CURRENT STATE: the comprehensive 32-scenario install-recovery re-run (GitHub Actions run 27715901866, on 78e770ac) is LIVE. When it is 100% green → cut rc.04. Any red → triage by class, fix, re-run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 #1 Comprehensive install-recovery run = 100% GREEN (all ~30 scenarios) on a commit containing all rc.04 code
- [ ] #2 #2 The two throwaway-build edge-case scenarios (binary-swap-kill + 4-rollback-kill) fixed and green — STATBUS-074
- [ ] #3 #3 Any VM-bootstrap infra blip cleared by a clean re-run, not masking a code red
- [ ] #4 #4 rc.04 tag cut off the green commit; the tag-push comprehensive run also green
- [ ] #5 #5 King gives the explicit cut on a fully-green run
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
RUN 27683157288 RESIDUALS FIXED + COMMITTED (foreman, 2026-06-17), both harness-only, master now e6c85c193:
1. Fabricate freshness (STATBUS-076) — fabricate ran the HEAD ./sb on the old tree -> staleness hard-fail. FIX = run fabricate with the tree-coherent binary (reorder). Committed 7f305f70d. Foreman caught + corrected a mechanic over-application (mid-tx-kill reverted, archivebackup-resume repositioned) before commit.
2. Quiesce-mask (STATBUS-073) — SIGKILL quiesce's `mask --runtime` paired with a plain `unmask` left the unit masked -> direct `systemctl start` failed (watchdog, resume-died-rollback). FIX = `unmask --runtime`. Committed e6c85c193.
HOLDING the re-run until run 27683157288 completes (batch any 3rd residual into ONE re-run on e6c85c193). PRODUCT unchanged (both fixes are test scaffolding). PATH: run completes -> characterize full residual -> (fix any 3rd) -> ONE comprehensive re-run -> if 100% green, cut rc.04 (King's bar).

RUN 27683157288 COMPLETE (3a0d6e6dd, the quiesce-only commit BEFORE my fixes): 16 PASS / 14 FAIL. Foreman classified all 14 by signature:
- FRESHNESS (7): binary-swap/backup/checkout-kill, between-migrations, container-restart, mid-migration, 4-rollback-kill → FIXED by e6c85c193 (reorder 7f305f70d).
- MASKED-UNIT (2): archivebackup-watchdog, watchdog-reconnect → FIXED by e6c85c193 (unmask --runtime).
- INFRA (1): stage-a-killed-migrate (vm-bootstrap.sh:360 SSH blip) → re-runnable.
- FLAG-ABSENT after kill (4) → GENUINELY-NEW 3rd class, NOT fixed by e6c85c193: archivebackup-resume, mid-tx-kill, resume-died-rollback, 4-rollback-restore-watchdog. All `✗ expected flag file present after kill`. Filed STATBUS-077; architect diagnosing product-vs-harness (could be ALBANIA-CRITICAL if executeUpgrade doesn't write the in-progress flag before the kill point — a no-remote-rescue box's mid-upgrade crash would be unrecoverable). This was RUN A's Cat A, MASKED by the quiesce-rollback, now unmasked.
SO: e6c85c193 fixes 9 of 14; infra re-runs clean; the 4 flag-absent need STATBUS-077's fix. RE-RUN HELD until STATBUS-077 lands, then ONE comprehensive re-run batches all (9 + 4 + infra) on the combined commit. The doctrine working: each run peels one layer.
<!-- SECTION:NOTES:END -->
