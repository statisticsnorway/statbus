---
id: STATBUS-068
title: >-
  rc04-recovery-regression: comprehensive run 19 reds = 4 gating modes + canary
  follow-up; fix-forward, no revert
status: In Progress
assignee: []
created_date: '2026-06-16 22:03'
updated_date: '2026-06-16 22:36'
labels:
  - install-recovery
  - rc.04
  - regression
  - architect-plan
  - gating
dependencies: []
priority: high
ordinal: 68000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rc.04 comprehensive install-recovery run 27645059996 (commit 537c56b48, all 33 scenarios): 13 PASS / 19 FAIL (+ discover/cleanup pass). NOT a systemic product regression — the recovery happy-paths (0-happy-install, 0-happy-upgrade) + several recovery scenarios pass. Architect root-caused (code-trace), foreman verified firsthand (spot-checked 3 new postswap reds = all known modes). NO REVERT: STATBUS-060 EXPOSED latent bugs by routing recovery through the real operator path; reverting re-buries them. Baseline: suite was ~green at bb4848dd45, 1 red at 7c7314184; the spread is mostly a PRE-EXISTING harness race the heavier 33-run widened.

MODE MAP + FIXES (the 19 reds):
#1 origin/master — install.sh edge RESCUE `git fetch origin master` + `git checkout -B current origin/master` fails (exit 128) on single-branch --depth1 --branch <tag> clones. FIXED FORWARD: cd00d4a6d (explicit +master:refs/remotes/origin/master refspec). [checkout-kill-legacy]
#2 staleness self-heal cascade — test inject mode stages HEAD binary on a mismatched tree → freshness git-diff fails → stalenessGuard self-heals via `make` → exits on the toolchain-less VM → ./sb install aborts before the kill → "flag present after kill" fails. FIX: STATBUS_INJECT_AT carve-out in cli/cmd/root.go (architect-designed; HELD for King nod — guard change keyed on the never-in-prod test-injection env var, validated by inject.Validate). Covers all 17 inject scenarios. [checkout-kill, mid-migration-kill, ...]
#3 fabricate race — fabricate_scheduled_upgrade_row INSERT...ON CONFLICT DO UPDATE fires AFTER-UPDATE pg_notify; the running upgrade service (NOTIFY listener + poll tick that also plants the 'available' row) claims the scheduled row before the inject `./sb install` → StateNothingScheduled → step-table → exit 0 → kill never fires. FIX: quiesce the upgrade unit before fabricate in all fabricate+inject scenarios (mechanic implementing, architect option-a). Pre-existing timing; 33-run widened the window. [backup-kill, binary-swap-kill, container-restart-kill, ...]
#5 archivebackup psql — `./sb psql` rc=1 in recovery data-fabricate; harness swallowed stderr. Operator surfacing it (data-helpers.sh) so it's diagnosable on re-run. [archivebackup-resume/-watchdog, resume-died-rollback, ...]
CANARY (STATBUS-067, NON-gating real product bug follow-up): resumePostSwap completes on container-health alone → silent corruption on post-swap kill mid-migration. [3-postswap-migrate-killed-after-commit, 3-postswap-migration-deterministic-error]
1-boot-startup-timeout — test-timing flake, FIXED (9d01ab61b).
PRE-EXISTING KNOWN-REDS (likely underlie a few, confirm on re-run): STATBUS-027 mid-tx-kill, STATBUS-028 4-rollback-kill, STATBUS-029 5-install-stage-a-killed-migrate. Uncategorized (likely #2/#3/#5): 5-install-drifted-unit-reconciled, 3-postswap-watchdog-reconnect, 4-rollback-restore-watchdog, 3-postswap-between-migrations-kill.

PATH TO GREEN: commit gating fixes (#1 done; #2 carve-out [King nod]; #3 quiesce; #5 psql) → push → ONE re-run reveals the genuine residual. CRITICAL: #2 + #3 must BOTH land — the carve-out alone can shift checkout-kill from #2 into the #3 race.
KING DECISIONS PENDING: (a) carve-out nod; (b) canary include-in-rc.04 vs priority follow-up (foreman rec: follow-up).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
OVERNIGHT 2026-06-17 (foreman) — gating set now nearly complete:
- #1 origin/master: COMMITTED cd00d4a6d.
- 1-boot-startup-timeout: COMMITTED 9d01ab61b.
- #3 fabricate→dispatch race quiesce: COMMITTED ab4a4dcad — helper quiesce_upgrade_service (wedge-helpers.sh) + 13 fabricate+inject scenarios. Foreman byte-level review CAUGHT a coverage miss: 3-postswap-mid-tx-kill sets its inject via ENV_PREFIX (not a bare STATBUS_INJECT_AT= line), which the mechanic's grep missed; added it. Intentionally NOT quiesced: migration-timeout (service must stay live), migrate-killed-after-commit (comment-only inject mention).
- #5 archivebackup psql-stderr-swallow: COMMITTED 11122f86f (diagnostic — surfaces the real psql error on re-run; also fixed an operator `||true;rc=$?` bug that would have reported a FAILED fabricate as success).
- #2 staleness carve-out: RECONSTRUCTED + pre-staged at tmp/carve-out-candidate.md (exact root.go Edit + tmp/commit-carveout.txt). Tree stays CLEAN; under independent architect verify; HELD for King nod. Mechanism confirmed in-tree at 1-boot-startup-timeout.sh:101-110; safety-checked every 'stale'/'self-heal' scenario (others are stale-FLAG / stale-UNIT, not the binary guard). Production-inert (STATBUS_INJECT_AT harness-only, inject.go:69-70).

MORNING = ONE BUTTON: King nods carve-out → apply tmp/carve-out-candidate.md Edit → build → commit (tmp/commit-carveout.txt) → push → trigger ONE comprehensive re-run. Re-run reveals the genuine residual (STATBUS-027/028/029 pre-existing reds + #5's real psql error + the non-gating canary 067). #2+#3 both landing is required (carve-out can shift checkout-kill into the now-quiesced race).

UPDATE (foreman, overnight 2026-06-17 cont.):
- CARVE-OUT (#2): architect independently VERIFIED — APPROVE as-is. Production-inert (byte-identical on real hosts; every STATBUS_INJECT_AT setter is a harness scenario, zero in cli/ops/service/timer, no os.Setenv), placement-clean (doesn't bypass the no-identity hard-fail or the STATBUS-065 forward-flag defer), and the BROAD scope is correct: under injection, binary staleness is ALWAYS deliberate harness orchestration (never the 'forgot to rebuild' hazard the guard exists for), and executeUpgrade re-invokes non-selfheal ./sb children that inherit the env — a narrower scope would spuriously abort them. Still pre-staged (tmp/carve-out-candidate.md), tree-clean, HELD for King nod.
- #3 INVARIANT COMPLETED + committed fc742bd4f (follow-up to ab4a4dcad). Architect post-commit cross-check found the '13 inject-dispatch' framing left 6 of 19 fabricate callers un-quiesced (only 2 documented). Now uniform: quiesce ADDED to worker-ddl-deadlock (genuine gap — now fails at the R1 DDL point, not the dispatch race; prerequisite for R1 to ever validate), checkout-kill-legacy, and both skip-default canary repros (inside _fabricate_in_progress_row, `>&2`). DOCUMENTED the 2 service-dispatch exclusions (0-happy-upgrade, migration-timeout). Rule recorded on quiesce_upgrade_service (wedge-helpers.sh). 17/19 quiesced, 2 doc'd exclusions, 0 gaps, bash -n clean.

GATING SET NOW COMPLETE EXCEPT THE CARVE-OUT (King nod): cd00d4a6d (origin/master) + 9d01ab61b (1-boot) + ab4a4dcad + fc742bd4f (#3) + 11122f86f (#5 capture). Go test green on current HEAD. Morning = King nods carve-out → apply tmp/carve-out-candidate.md → build → commit → push → `gh workflow run install-recovery-harness.yaml --ref master`.
<!-- SECTION:NOTES:END -->
