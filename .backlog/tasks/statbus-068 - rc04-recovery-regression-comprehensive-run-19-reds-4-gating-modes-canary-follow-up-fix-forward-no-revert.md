---
id: STATBUS-068
title: >-
  rc04-recovery-regression: comprehensive run 19 reds = 4 gating modes + canary
  follow-up; fix-forward, no revert
status: In Progress
assignee: []
created_date: '2026-06-16 22:03'
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
