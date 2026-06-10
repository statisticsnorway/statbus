---
id: STATBUS-017
title: >-
  rune-wedge-fix: SOLVED + PROVEN on real VMs (fall-through to recovery) —
  awaiting King ratification of the diff (direction a, roll-back)
status: In Progress
assignee: []
created_date: '2026-06-08 21:46'
updated_date: '2026-06-10 05:19'
labels:
  - install-recovery
  - recovery
  - product-bug
  - needs-king-decision
  - rune-wedge
dependencies: []
references:
  - 'cli/internal/upgrade/service.go:1644'
  - 'cli/internal/upgrade/service.go:1656'
  - 'cli/internal/upgrade/service.go:838'
  - 'cli/cmd/install_upgrade.go:198'
  - 'cli/internal/migrate/migrate.go:829'
  - 'doc/diagrams/upgrade-timeline.plantuml:144'
priority: high
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CONFIRMED PRODUCT RECOVERY BUG (independent code-trace: architect + foreman, overnight 2026-06-08). FIRST confirmed product recovery bug of the campaign — and it is the exact 40h NO/rune wedge this campaign exists to prevent. Bears DIRECTLY on the NO (Norway) rollout: rolling out NO now risks repeating the wedge.

== THE BUG ==
Both recovery entrypoints run a "schema-skew guard" `./sb migrate up` BEFORE recoverFromFlag. On a half-applied migration that migrate-up FAILS and returns WITHOUT restoring, so the intended forward-then-restore (recoveryRollback) is never reached → boot-loop / non-zero-exit wedge instead of restore→rolled_back.

Evidence:
- Service boot: boot-migrate-up at service.go:1644 runs BEFORE recoverFromFlag at :1669, UNCONDITIONALLY (the flag.Holder==Service && Phase==PostSwap block at :1561-1565 is only a fmt.Printf, NOT a skip). On failure: markTerminal("BOOT_MIGRATE_UP_FAILED")+return err (:1656-1658) — markTerminal only writes an audit file (NO snapshot restore, NO recoverFromFlag). systemd Restart=always → migrate fails again → StartLimit → unit failed.
- Inline (./sb install crash recovery): cli/cmd/install_upgrade.go:198 runs migrate up; on failure `return "crash recovery: boot migrate up"` (:199); RecoverFromFlag (:205) never reached.
- The forward-recovery branch (recoverFromFlag :838-927, incl the migrate.Up → "relation already exists" → recoveryRollback restore at :879) is DEAD CODE for service-held flags: :739 (HolderInstall) returns, :755 (Resuming) / :774 (PostSwap) / :822 (PreSwap=="") each return, so a service-held flag (phase always in {"",post_swap,resuming}) never reaches :838+.

== WHY a/b/d PASS but c/e WEDGE (dividing line) ==
Recovery's schema-skew migrate-up SUCCEEDS iff the migration re-applies cleanly:
- (a) kill before tx (migrate.go:387): N never committed → clean re-apply → COMPLETED. (3-postswap-mid-migration-kill GREEN)
- (b) kill inside tx pre-commit: Postgres rolls back → clean re-apply → COMPLETED. (new cell)
- (d) kill after db.migration INSERT (migrate.go:896): N recorded, N+1 clean → COMPLETED. (3-postswap-between-migrations-kill)
- (c) after-commit (migrate.go:829/830): re-apply → "relation already exists" → migrate-up FAILS → WEDGE.  <-- THE RUNE WEDGE
- (e) deterministic migration error: re-apply errors every time → migrate-up FAILS → WEDGE.
This is why 3-postswap-migrate-killed-after-commit was never green ("deferred", STATBUS-013) — the deferral was the SYMPTOM of this bug.

== CORRECTS PRIOR CONCLUSIONS ==
- Overturns the prior "0 confirmed product recovery bugs" for the central scenario.
- Foreman previously told the King the after-commit wedge is handled by forward-once-then-restore (service.go:877-913); that branch is DEAD code. Corrected.
- doc/diagrams/upgrade-timeline.plantuml:144-146 claims the after-commit cell "RESTORES → rolled_back (the rune shape)" — that is INTENDED, NOT current reality. Diagram being corrected to mark INTENDED vs ACTUAL-BUG.

== CANDIDATE FIX DIRECTIONS (King decides — NOT implemented) ==
a. On schema-skew migrate-up FAILURE, route to recoveryRollback (restore snapshot → rolled_back) instead of markTerminal+return/boot-loop — realize forward-once-then-restore at the boot-migrate site.
b. Run recoverFromFlag BEFORE the schema-skew migrate-up when a post-swap / in-progress flag is present (restore path owns the failure).
c. Fold the db.migration record INTO each migration's own transaction (close the commit↔record window so the after-commit RED state cannot arise). Bigger; touches migration authoring.
TENSION: the rc.65 schema-skew migrate-up exists to bring schema to HEAD before any public.upgrade query (rc.63 renamed columns → SQLSTATE 42703 otherwise). It cannot simply be removed; the fix must preserve schema-to-HEAD for the binary's queries while not letting a half-applied migration's re-run failure pre-empt the restore.

== EMPIRICAL CONFIRMATION (in progress) ==
Architect building a deterministic reproducer (fabricate the after-commit RED state directly, not via fragile kill-timing) asserting the intended rolled_back — currently RED, demonstrating the wedge on a real VM. Foreman to run + attach the run URL.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 King decides the fix direction (a/b/c below or other)
- [x] #2 Empirical reproducer captured (real-VM run URL) demonstrating the current wedge (BOOT_MIGRATE_UP_FAILED / boot-loop / non-zero, NOT rolled_back)
- [x] #3 Fix implemented in recovery code (King-gated — not done autonomously)
- [x] #4 3-postswap-migrate-killed-after-commit + the migration-error scenario go GREEN (state=rolled_back) on real VMs
- [x] #5 doc/diagrams/upgrade-timeline.plantuml + doc/upgrade-timeline.md updated to match the fixed behavior
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ARCHITECT RECOMMENDATION (2026-06-09, independent code-trace; King decision pending on AC#1). Captured in backlog per project discipline (durable record, not tmp).

VERIFIED (all 3 ticket claims confirmed, one sharpened):
(i) schema-skew `migrate up` runs BEFORE recoverFromFlag on BOTH entrypoints — service.go:1644 then :1669; install_upgrade.go:198 then :205. The :1561-1565 Holder==Service&&Phase==PostSwap block is only a fmt.Printf, NOT a skip.
(ii) on failure → markTerminal+return (service) / inline return (install), NO restore. markTerminal (service.go:37) writes an audit file only.
(iii) the :838-927 forward-then-restore branch (incl migrate.Up :879) is DEAD for EVERY service-flag value: FlagPhasePreSwap=='' caught at :822; only {'',post_swap,resuming} are ever written → all return before :838. (Corrects the earlier ':877-913 handles it' claim.)
SHARPENED: downstream restore machinery is correct+complete, merely pre-empted. post_swap→resumePostSwap→applyPostSwap step-10 migrate fails→postSwapFailure→rollback→restore→rolled_back already works. Fix = stop the guard pre-empting it, NOT build a new restore path.

RECOMMENDED FIX = Direction (a), fall-through-to-recovery on guard failure: when boot-migrate-up fails AND a service-held flag is present (flag.Holder==HolderService), log + fall through to recoverFromFlag instead of markTerminal/return. Keep markTerminal+return for the no-flag / install-held case (legitimate stale-schema refusal). Symmetric change at install_upgrade.go:198.
RATIONALE: preserves schema-to-HEAD for every case migrate CAN succeed; defers to the already-correct snapshot-restore path only in the exact case the guard can't succeed — precisely where restore is the right outcome.
REJECTED (b) recover-before-guard: resumePostSwap:4180 hard-fails 42703 on from_commit_version → reintroduces the bug the guard closes.
REJECTED (c)-alone (fold record into migration tx): cannot fix cell (e) (deterministic error → only restore works) AND makes the after-commit cell forward-COMPLETE, subverting AC#4's rolled_back target. (c) = good follow-up hardening ticket, not the gate.
KEY RISK: residual rc.63-transition sub-case — in-flight upgrade straddling the column-rename migration, killed BEFORE it, would 42703 in recovery's own queries. Historical (rename long-applied on rune + all live deployments), not the steady-state rune risk; AC#4 only needs the 2 named scenarios green.
OPEN QUESTION (King, AC#1): when a half-applied migration can't be re-run during recovery — ROLL BACK to the pre-upgrade snapshot (recommended, matches AC) or PUSH FORWARD to complete? Default unless told otherwise: ship (a)→rolled_back, file (c) as follow-up.

═══ KING AUTHORIZED — DRIVE TO SOLVED OVERNIGHT (2026-06-09 ~21:25Z) ═══
King clarified the workflow: WE WORK ON MASTER. Push to master → Images builds the seed → harness tests it. No release/RC is cut, so nothing deploys to NO/cloud. The 'King-gated, do not touch recovery code' caution was about ROLLOUT, not about committing to master — so I am CLEARED to implement + push + VM-prove the fix tonight. King wants 017 solved by morning.

DIRECTION: proceeding on the architect's adversarially-verified recommendation = direction (a), roll-back: when boot-migrate-up (the schema-skew guard) FAILS and a service-held flag is present, fall through to recoverFromFlag (the already-correct restore path → state=rolled_back) instead of markTerminal+return/boot-loop. Symmetric change at service.go (~1644/1656) and install_upgrade.go (~198). Keep markTerminal+return for the no-flag / install-held case. File (c) (fold db.migration record into each migration tx) as a follow-up hardening ticket, NOT the gate.

OVERNIGHT SEQUENCE:
1. Engineer fixes the reproducer fabrication (NOTIFY-race: live upgrade unit picks up the fabricated 'scheduled' row → stops db) — harness-only. Commit A → push → Images.
2. Run the 2 reproducers on Commit A → they hit the wedge → RED with BOOT_MIGRATE_UP_FAILED = AC#2 PROOF captured (the 'before').
3. Architect finalizes the execution-ready fix plan (direction a) incl. seeding a real pre-upgrade-active snapshot so the restore lands rolled_back not failed. Engineer implements. Architect adversarially reviews the diff. I review.
4. Commit B: recovery fix + doc/diagrams/upgrade-timeline.plantuml + doc/upgrade-timeline.md (AC#5) + flip the reproducer KNOWN-RED headers. Push → Images.
5. Run the 2 reproducers on Commit B → GREEN (state=rolled_back) = AC#3 + AC#4 proven on real VMs.
Morning deliverable to King: the diff, the RED-proof run URL, the GREEN run URL, plain-language writeup.

EXECUTION-READY FIX PLAN (architect, 2026-06-09): tmp/plans/architect-017-fix-plan.md. King authorized direction (a) ON MASTER. Two product edits + reproducer/doc changes. Line numbers re-read against current master.

PRODUCT EDIT 1 — service.go boot-migrate-up failure handler (1644-1659): between the ErrCommandTimeout orphan-cleanup and markTerminal, branch on the flag: `if flag,_,ferr := ReadFlagFile(d.projDir); ferr==nil && flag!=nil && flag.Holder==HolderService { log; fall through to recoverFromFlag (:1669) } else { markTerminal(BOOT_MIGRATE_UP_FAILED)+return }`. ReadFlagFile exported at :562 (*UpgradeFlag,bool,error); HolderService="service" :182.
PRODUCT EDIT 2 — install_upgrade.go inline (198-199): symmetric, upgrade.ReadFlagFile/upgrade.HolderService (pkg imported :12, svc :133, sb :159). Predicate: service-held flag present → fall through; no-flag/install-held → refuse. Blast radius zero in green scenarios (only fires when boot-migrate-up FAILS).
The wedge flag is Phase=resuming → recoverFromFlag :755 Resuming one-shot latch → recoveryRollback → rollback → restore → rolled_back + os.Exit(75). Restore machinery correct+complete, merely pre-empted.

TWO NON-OBVIOUS FINDINGS the engineer MUST handle (beyond the King brief):
(1) The rolled_back-vs-failed determinant is the GIT-restore, NOT the snapshot. recoveryRollback's prev=d.version (NULL from_commit_version) is a non-ref describe string → restoreGitState falls back to the `pre-upgrade` branch; the fabricated reproducers never pin it → ABORT (service.go:4625-4704) → state=failed+exit1. Green sibling container-restart-kill only works because REAL executeUpgrade pins pre-upgrade (service.go:3480). FIX: reproducer must `git branch -f pre-upgrade HEAD` before fabricating. (Absent snapshot alone → restoreDatabase no-ops to nil (exec.go:698) → still rolled_back, just un-restored DB — so the FUTURE note's 'else failed' was imprecise.) The snapshot (R2) is for a FAITHFUL restore (orphan removed); seed it as an rsync of PGDATA taken AFTER the in_progress row but BEFORE the orphan.
(2) Cell (e) LATENT RE-WEDGE: both reproducers `install` the synthetic migration UNTRACKED (migrate sh:138, det-error sh:126); `git checkout -f pre-upgrade` does NOT remove untracked files → after recovery clears the flag, the erroring migration re-runs on the next boot with no recovery owner → boot-loop → NRestarts unbounded → assertion fails. FIX: commit the synthetic migration as a TRACKED migrations-only commit on top of pinned pre-upgrade so restoreGitState drops it. SAFE re: rc.65 staleness — freshness.IsStale diffs only `cli/` (check.go:95), migrations-only shows no cli/ drift → no self-heal rebuild.

ALSO: the reproducers' error-match assertion `"forward failed: .*; auto-restored from"` (migrate sh:354, det-error sh:307) is WRONG for the Resuming-latch path — change to `"UPGRADE_DIED_DURING_RESUME.*rolled back to the snapshot"`.
Doc edits (AC#5): plantuml move both reproducers KNOWN-RED→GREEN + rewrite cell(2)/(e) INTENDED-vs-ACTUAL to the fall-through behavior; upgrade-timeline.md add the defer-to-recoverFromFlag sentence at the boot-guard (~:65). rc.63 residual = out-of-scope historical. Verify: run the 2 reproducers on Hetzner → rolled_back + regression-check the green postswap suite.

EXECUTION-READY FIX PLAN written (architect): tmp/plans/architect-017-fix-plan.md. Engineer now implementing; architect on review-standby; foreman commits.
PRODUCT EDITS (minimal, inert except on the wedge): (1a) service.go boot-migrate-up failure handler — if ReadFlagFile gives flag!=nil && flag.Holder==HolderService, log + FALL THROUGH to recoverFromFlag(:1669) instead of markTerminal+return; keep refuse for no-flag/install-held. (1b) symmetric at install_upgrade.go ~198→205. Predicate: a service-held flag exists only for an in-progress upgrade (phase ∈ {PreSwap'',PostSwap,Resuming}, all restore-routed); PreSwap kill never reaches this branch (dies before migrations → guard succeeds).
KEY ADVERSARIAL DISCOVERIES (would have mystery-failed a naive GREEN run): R1 the reproducers MUST pin the `pre-upgrade` git branch (git branch -f pre-upgrade HEAD) — the ACTUAL failed-vs-rolledback determinant (restoreGitState ABORT → state=failed otherwise), NOT the DB snapshot. R2 seed a real pre-upgrade-active DB snapshot (else restore no-ops → hollow rolled_back). R3 the synthetic migration must be a TRACKED commit (migrations-only, so rc.65 freshness guard stays silent) or `git checkout -f pre-upgrade` won't remove it → cell (e) RE-WEDGES + boot-loops. Stage-1 ordering: pin → push tracked migration → fabricate in_progress row → seed snapshot → precreate orphan → fabricate resuming flag. 2b: error-match assert must change to UPGRADE_DIED_DURING_RESUME.*rolled back to the snapshot (the real Resuming-latch message; the old 'forward failed...auto-restored' was the DEAD :877 branch). 2c: flip KNOWN-RED headers → expected-green + faithfulness assert (orphan gone / synthetic migration absent). rc.63-transition residual = OUT OF SCOPE (historical, no guard).
VERIFY: engineer compiles (./dev.sh build-sb) + bash -n; then GREEN run of the 2 reproducers (expect state=rolled_back, error~UPGRADE_DIED_DURING_RESUME, NRestarts≤2, orphan gone) + regression-check the green postswap suite (fix is inert there but path is shared).

✅ AC#2 CAPTURED — wedge proven on real Hetzner VMs. Run 27237385049 @ bdc83a466 (https://github.com/statisticsnorway/statbus/actions/runs/27237385049), conclusion=failure (RED-by-design = the proof). Both reproducers got PAST Stage-1 (fabrication fix bdc83a466 held — db stayed up) and REACHED the wedge:
- cell 2 (migrate-killed-after-commit): ERROR relation "harness_after_commit_sentinel" already exists → 3× 'Error: boot migrate up: exit status 1' → boot-loop NRestarts=2 → row state=in_progress rolled_back_at=∅.
- cell e (deterministic-error): ERROR 'harness deterministic migration error (STATBUS-017 cell e)' → same boot-loop → state=in_progress.
Stage-4 intended-green RED by design: 'upgrade row state mismatch: expected=rolled_back actual=in_progress'. Evidence: tmp/operator-wedge-PROOF-27237385049.md.
This is the empirical 'before' — the recovery fix (engineer implementing now) must flip both to state=rolled_back (AC#4). AC#1 = King authorized solving on master + proceeding direction (a)/roll-back (formal morning confirmation pending; no objection raised).

FIX COMMITTED + REVIEWED (2026-06-10 ~22:20Z). Three commits on master: 584919285 (PRODUCT recovery fix — service.go + install_upgrade.go, the fall-through-to-recoverFromFlag on a service-held flag), 93074ba71 (reproducers R1/R2/R3 + seed_pre_upgrade_snapshot helper + doc/diagrams/upgrade-timeline.plantuml + doc/upgrade-timeline.md), 686ba94e1 (cosmetic banner KNOWN-RED→EXPECTED-GREEN). Engineer-implemented per the architect plan; build exit 0 + go vet clean + bash -n clean. ARCHITECT ADVERSARIAL REVIEW = PASS-with-fixes (independently verified the predicate, true fall-through, recovery trace landing rolled_back via degraded=false, R1/R2/R3 + Stage-1 ordering, R2 path-match to backupRoot()/dbVolumeName, R3 staleness-safety, assertions); the one required fix (doc/upgrade-timeline.md operator-narrative now names the UPGRADE_DIED_DURING_RESUME path) was applied. Foreman independently reviewed the product diff (clean, minimal, inert-in-green) + the seed helper (mirrors backupDatabase, fails loud, append-only zero-blast-radius).
AC#3 (fix implemented) + AC#5 (docs) DONE. AC#1 = King authorized direction (a)/roll-back on master; formal morning confirmation of the diff pending (King-gated review). AC#4 = GREEN run dispatching once Images builds the 686ba94e1 seed (expect both reproducers state=rolled_back, error~UPGRADE_DIED_DURING_RESUME, NRestarts≤2, orphan gone). Then comprehensive run for breadth + product-fix regression check.

GREEN run 27239835249 @ 686ba94e1 = FAILURE — but NOT the product fix. Both reproducers died at Stage-1 in the NEW seed_pre_upgrade_snapshot helper, BEFORE recovery ran (product recovery code never exercised — 017 fix NOT refuted). ROOT CAUSE: harness transport bug — the helper's `VM_EXEC bash -c '<multi-line body>'` got mangled (printf %q collapse): the VM bash shows the body on one line with $vol/$dest EMPTY (`if [ -z "" ]`, `mkdir -p ""`, `-v "":/source`). Same class as the recurring VM_EXEC multi-line failures. The R1 pin + R3 tracked-migration commit + the scheduled-row fabricate all SUCCEEDED (log: 'pre-upgrade -> 686ba94', 'synthetic migration committed ... tracked on top of pre-upgrade') — only the snapshot-seed transport broke. This is the GREEN run doing its job (caught a real harness bug the static review couldn't see — test-to-know). Engineer rewriting the helper transport to the proven mktemp+scp+ssh pattern (lib/data-helpers.sh, still 2-reproducer-only); architect re-reviews; then re-commit → Images → re-run. Comprehensive run HELD until the GREEN re-run clears (harness concurrency serializes; 017 GREEN is priority).

✅✅ AC#4 PROVEN — 017 SOLVED + PROVEN RED→GREEN ON REAL VMs. GREEN re-run 27241262390 @ f31ce6f86 = conclusion=SUCCESS, 'Summary: 2 passed, 0 failed' (https://github.com/statisticsnorway/statbus/actions/runs/27241262390). Both reproducers — the SAME ones that boot-looped in the RED proof (27237385049) — now restore cleanly:
- 3-postswap-migrate-killed-after-commit (cell c): ✓ faithful restore (orphan gone, synthetic migration unrecorded + file removed = a REAL restore, not hollow) → NRestarts=0 → PASS 'rune wedge FIXED — restores to rolled_back'.
- 3-postswap-migration-deterministic-error (cell e): row state=rolled_back, error='UPGRADE_DIED_DURING_RESUME ... rolled back to the snapshot', NRestarts=0 (no boot-loop) → PASS.
The before/after pair (RED 27237385049 → GREEN 27241262390) is the empirical proof: same fabrication, the only change is the recovery-code fix (584919285) + the snapshot-restore preconditions.

017 STATE: AC#2 (RED proof) + AC#3 (implemented) + AC#4 (GREEN proof) + AC#5 (docs) ALL DONE. The fix is SOLVED + PROVEN end-to-end. AC#1 (King's formal direction confirmation) + the final close await the King's MORNING review of the product diff (584919285) — leaving the task In Progress + this AC for the King to ratify (recovery code is King-gated; the King reviews the diff, confirms direction (a)/roll-back, closes). If the King wants push-forward instead of roll-back, that's a redirect; the work + proof are done for (a).
<!-- SECTION:NOTES:END -->
