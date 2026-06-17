---
id: STATBUS-075
title: >-
  cut-rc04: release-candidate gate — the single tracker for what we are waiting
  on to cut rc.04
status: In Progress
assignee: []
created_date: '2026-06-17 11:04'
updated_date: '2026-06-17 12:25'
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
THE entry that answers "are we there yet" for rc.04. Single source of truth for the cut; STATBUS-073 holds the forensic triage detail beneath it.

GOAL: cut the rc.04 tag.

ALL rc.04 CODE IS LANDED ON MASTER (verified ancestors of HEAD):
- 23c5c33f1 — recovery rollback grounded on the source CommitSHA + recovery-boot checkout gated to PostSwap/Resuming (STATBUS-061/062).
- 1e02a1797 — post-swap self-heal gated on migration-complete, no silent corruption (STATBUS-067 canary; code is IN rc.04, reproducer-fidelity validation parked to STATBUS-071).
- 9bdba03cc — harness: config-generate before fabricate psql (RUN-A Category C fix).
- 3a0d6e6dd — harness: SIGKILL-class quiesce, removes the quiesce-rollback footgun that corrupted 13/14 of RUN A (STATBUS-073 root cause).

THE ONLY BLOCKER = the comprehensive install-recovery gate at 100% GREEN. KING RULING 2026-06-17: HOLD FOR 100% GREEN — NO "confirmed-known-and-acceptable reds" carve-out. Even a residual of only {a VM-bootstrap infra blip + the two throwaway-build edge-case scenarios} does NOT permit a cut.

WHAT WE ARE WAITING ON (live):
1. Comprehensive re-run 27683157288 (on 3a0d6e6dd) to land — validates the SIGKILL-quiesce fix across ~30 scenarios. Expect ~13 of 14 RUN-A reds cleared.
2. The two throwaway-build edge-case scenarios fixed and green — STATBUS-074 (mechanic, on the critical path by the 100%-green bar).
3. Any VM-bootstrap infra blip cleared by a clean re-run (must not mask a code red).
4. Then: cut the rc.04 tag off the green commit; the tag-push comprehensive run must also be green.

DISPOSITION OF THE OTHER IN-PROGRESS ITEMS RELATIVE TO THIS CUT (their fate is decided by the run, no independent driving needed):
- STATBUS-025 (matrix/6h-ceiling): machinery DONE + proven; remaining ACs fall out of a green run. THIS run IS the matrix.
- STATBUS-061: code shipped; validated when the 2-preswap scenarios go green in the run.
- STATBUS-026/027/029: harness fixes committed; "green pending the run". Run is the verdict.
- STATBUS-028: rc=75 layer committed; its SECOND layer (edge-swap) is STATBUS-074.
- STATBUS-073: the forensic gate-residual triage (RUN A 18/14 -> one root cause).
- STATBUS-067: canary CODE is in rc.04; reproducer-fidelity validation is post-rc.04 (overlaps STATBUS-071) — NON-gating.
- STATBUS-031 (rollback-watchdog): King ruled it gates the STABLE/Norway promotion, NOT this prerelease — NOT an rc.04 blocker. Its GREEN scenario rides this run; the RED->GREEN proof is separate.
- STATBUS-070 (run-to-know doctrine): doctrine doc done + linked; per-scenario catalogue clarity polish remains — NON-gating.

DOCTRINE: only the run tells the truth (doc/install-upgrade-testing.md). Do NOT pre-judge "will it be green" — the run decides. Cut is the King's call off a fully-green run.
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
<!-- SECTION:NOTES:END -->
