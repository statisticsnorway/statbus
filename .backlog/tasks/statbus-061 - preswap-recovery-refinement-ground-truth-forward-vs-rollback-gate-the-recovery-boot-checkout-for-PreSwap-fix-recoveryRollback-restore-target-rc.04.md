---
id: STATBUS-061
title: >-
  preswap-recovery-refinement: ground-truth forward-vs-rollback + gate the
  recovery-boot checkout for PreSwap + fix recoveryRollback restore target
  (rc.04)
status: In Progress
assignee: []
created_date: '2026-06-16 00:35'
updated_date: '2026-06-16 09:55'
labels:
  - upgrade
  - recovery
  - robustness
  - architect-plan
  - rc.04
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/cmd/install_upgrade.go
  - test/install-recovery/lib/wedge-helpers.sh
  - test/install-recovery/scenarios/2-preswap-checkout-kill.sh
priority: high
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DESIGN/diagnosis only (rc.04). Refines STATBUS-059's defer-checkout recovery path, surfaced by the 2-preswap-checkout-kill scenarios (a)+(b) on d0992498a. The config-drift wedge (the charge) is DONE + 0-happy GREEN (09ac1f7e4 + 7cc6c1b48); this is the deeper preswap-recovery refinement. Refs: STATBUS-059 (defer-checkout), STATBUS-046 (at-target forward path), STATBUS-026 (scenario fidelity), STATBUS-039 (operator-one-action).

## Findings (verified, file:line)
1. (b) tree-not-restored-to-OLD — ROOT CAUSE is recoveryRollback, NOT the recovery-boot checkout. recoveryRollback (service.go:~2194) defaults the restore target to `prev := d.version` (the recovery binary's version = the TARGET in a HEAD recovery), overriding only when the row's from_commit_version is set. The harness-fabricated row has from_commit_version=null (log:3995) → prev=rc.03 → restoreGitStateFn (service.go:5381) resolves rc.03 (never reaches the pre-upgrade fallback) and checks it out → "Git state restored to 2026.06.0-rc.03…" (log:3905) → tree at TARGET. restoreGitState RAN and actively checked out rc.03 (its computed target) — it did NOT "fail to override" the recovery-boot checkout; it would restore to prev=d.version regardless of any prior checkout. PRE-EXISTING (a real upgrade sets from_commit_version=source → prev=OLD → correct).
2. The recovery-boot checkout (STATBUS-059: Service.Run ~1474 + runCrashRecovery ~164) runs for ANY service-held flag, checking out flag.CommitSHA (target) BEFORE boot-migrate-up. For a PreSwap flag (rollback) this makes boot-migrate apply TARGET migrations, but the PreSwap rollback's restoreDatabase is a no-op (empty backup, never-mutated volume) → git rolled to OLD + schema left at TARGET = schema/git MISMATCH. Defer-checkout-introduced.
3. (a) forward-complete-to-target (current==target HEAD recovery): CORRECT per STATBUS-039 (converge forward, one action, data intact). BUT it happened via the db-unreachable FALLBACK (flag absent — runtime log unavailable, can't root-cause the absence), not a deliberate ground-truth decision → fragile.

## The refinement (design)
(i) DELIBERATE forward-vs-rollback from GROUND TRUTH (STATBUS-046): recovery chooses resume-forward vs rollback from the flag's ground truth (phase, binary-at-target?, migrations-applied?), NOT a db-unreachable fallback or accidental branch. At-target + nothing-committed → deliberate forward-complete; genuine rollback-required (e.g. post-swap migration failure) → rollback.
(ii) GATE the recovery-boot checkout: run `git checkout flag.CommitSHA` ONLY for Phase==PostSwap/Resuming (resume needs the target tree for boot-migrate + config-gen). For PreSwap (rollback) DO NOT checkout the target — let the rollback's restoreGitState own the tree (→ OLD); avoids the schema-skew (finding 2).
(iii) FIX recoveryRollback's restore target: prefer the flag's from-version / the `pre-upgrade` branch (pinned to OLD by executeUpgrade) over `d.version`. d.version is exactly wrong when the recovery binary == target (finding 1).
(iv) HARNESS: fabricate_scheduled_upgrade_row (wedge-helpers.sh) must set from_commit_version so recovery has the source version — exposes/validates (iii).
(v) SCENARIO assertions (STATBUS-026): (a) target-binary recovery → assert forward-complete-to-target (state='completed', at target, data intact); (b) genuine-binary recovery → assert rollback to OLD with tree restored (after iii+iv).

## Critical files
service.go: recoveryRollback (~2188-2208), restoreGitStateFn (5381), Service.Run recovery-boot checkout (~1474), recoverFromFlag PreSwap (~920); install_upgrade.go runCrashRecovery (~164); wedge-helpers.sh fabricate_scheduled_upgrade_row; 2-preswap-checkout-kill*.sh.

## Verification
Both 2-preswap scenarios green: (a) forward-complete-to-target; (b) rollback-to-OLD tree restored. 0-happy stays green.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Recovery deliberately chooses forward-vs-rollback from flag ground truth (not the db-unreachable fallback) — STATBUS-046
- [ ] #2 Recovery-boot checkout (Service.Run + runCrashRecovery) gated to Phase==PostSwap/Resuming; PreSwap rollback does not checkout the target (no schema/git mismatch)
- [ ] #3 recoveryRollback restore target prefers from_commit_version / pre-upgrade over d.version (correct when recovery binary == target)
- [ ] #4 Harness fabricate_scheduled_upgrade_row sets from_commit_version
- [ ] #5 2-preswap-checkout-kill (a) asserts forward-complete-to-target; (b) asserts rollback-to-OLD with tree restored; both green + 0-happy green
- [ ] #6 King ruling recorded on rc.03 disposition (revert defer-checkout vs ship-as-is vs hold)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ACTIVATED 2026-06-16 — King chose Option B (fix-forward; NO revert; the defer-checkout commits stay on master). This task IS rc.04 and ships the recovery fix forward in the next candidate. AC#6 ruling = fix-forward (not revert, not ship-as-is). OWNERSHIP (disjoint files): architect implements (i)(ii)(iii) in cli/internal/upgrade/service.go + cli/cmd/install_upgrade.go; mechanic implements (iv) test/install-recovery/lib/wedge-helpers.sh now + (v) 2-preswap-checkout-kill assertions after the code lands; foreman reviews every diff byte-level; do-not-self-commit. VALIDATION: 0-happy + both 2-preswap green locally, then full comprehensive at max-parallel:3 (no quota raise needed) in change-first order (0-happy + recovery scenarios 2/3/4 first, 5-install last). Then cut rc.04 from validated master. Nothing ships until King okays the plan + foreman review.

CONCRETE ARTIFACTS (King's grounding directive, verified this session 2026-06-16):
- Arc under fix = commits 2f52f3b7f (defer-checkout) + bb4848dd4 (guard), shipped in rc.03 = tag v2026.06.0-rc.03 @ commit d0992498a2afac601978568606aed617bf8e9f2d.
- KEEP (validated): config-regen 7cc6c1b48 + image-extract 09ac1f7e4. 0-happy GREEN = CI run 27582053054 on commit 658c34ebd.
- Legacy-scenario baseline = release tag v2026.05.2 -> commit 50fd4325f9e2e4d8a91a4d02570a43c0bfbe103f. That binary's executeUpgrade writes from_commit_version = d.version (a VERSION STRING) at service.go:1286 (@ tag); reads it in recoveryRollback at service.go:1905 (@ tag). HEAD equivalents: write at service.go:1308 (ExecuteUpgradeInline) + 3478 (executeScheduled); read at 2190; pre-upgrade-branch fallback in restoreGitStateFn ~5388.
- Part (iv) fidelity (verified): a genuine v2026.05.2 crash row has from_commit_version SET to v2026.05.2's d.version (version string) -- NOT null, NOT a commit SHA. Harness must inject SB_VERSION_BEFORE (genuine version string), not OLD_COMMIT. Files: test/install-recovery/lib/wedge-helpers.sh write_preswap_wedge (~549/566); test/install-recovery/scenarios/2-preswap-checkout-kill-legacy.sh:133. Mechanic bounced to correct the value 2026-06-16.
- Comprehensive at max-parallel:8 (commit d0992498a) = CI run 27583439253: all 29 scenario jobs failed at VM creation (vm-bootstrap.sh:402) on Hetzner 'server limit reached' + 'Primary IP limit exceeded'. Stopgap max-parallel:3 = commit 9b7588596.

rc.04 PROGRESS (2026-06-16) — architect implemented (ii)+(iii), build/vet/test GREEN, do-not-committed. Diff: cli/internal/upgrade/service.go + cli/cmd/install_upgrade.go (49+/22-). Foreman reviewed byte-level + verified firsthand:
- (ii) recovery-boot checkout GATED to Phase==PostSwap/Resuming at BOTH sites (service.go Run ~1487 + install_upgrade.go runCrashRecovery ~172). PreSwap no longer checks out target → tree stays at source → no schema/git skew (finding 2 closed).
- (iii) recoveryRollback `prev := d.version` → `prev := ""`; empty routes restoreGitStateFn to the pinned `pre-upgrade` branch (= OLD COMMIT); from_commit_version override kept. VERIFIED safe: `git rev-parse --verify '^{commit}'` → fatal 'Needed a single revision' exit 128 → fallback at service.go:5409. (iii) is commit-grounded → compatible with STATBUS-062 either outcome.
- New structural guard tests pass: TestRecoverFromFlag_PhaseRoutingAndGroundTruthFirst + TestRecoveryRollback_FlockGateBeforeDestructiveWork.

REVERSAL of finding (v)(a) [architect, foreman-verified]: part (i) CANNOT be a principled ground-truth split between the two 2-preswap scenarios. Both recover with the HEAD/target binary, and boot-migrate runs BEFORE recoverFromFlag, so both read GT=AtTarget; they differ ONLY in working-tree position (OLD vs target) — an old-vs-new-checkout artifact, NOT real upgrade progress. A PreSwap kill = killed before the binary-swap commit boundary = deterministically ROLLS BACK to OLD. The overnight '(a)=forward-complete-to-target' was the db-unreachable-FALLBACK accident (flag absent), not principled. Deliberate-forward's full form == UN-RATIFIED STATBUS-046.

NEW part (v) direction: BOTH 2-preswap scenarios assert ROLLBACK-TO-OLD (do NOT reclassify (a) to forward-complete). Part (iv) from_commit_version STAYS (validates (iii)'s override path). AC#5 reworded accordingly.

KING DECISION (rc.04 scope) — A) ship (ii)+(iii): both PreSwap roll back to OLD [architect rec + foreman concur]; defer deliberate-forward to a ratified STATBUS-046 with a reproduction. B) pull deliberate-forward-(a)-completes in now (needs STATBUS-046 ratified + Run reorder + reopens schema-skew). AWAITING King ruling (= AC#6, now rc.04-scope not rc.03-disposition).
<!-- SECTION:NOTES:END -->
