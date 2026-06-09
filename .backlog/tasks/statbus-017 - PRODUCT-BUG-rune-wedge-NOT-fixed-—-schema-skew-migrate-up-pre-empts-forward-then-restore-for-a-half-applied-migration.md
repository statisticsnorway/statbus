---
id: STATBUS-017
title: >-
  PRODUCT BUG: rune wedge NOT fixed — schema-skew migrate-up pre-empts
  forward-then-restore for a half-applied migration
status: In Progress
assignee: []
created_date: '2026-06-08 21:46'
updated_date: '2026-06-09 21:27'
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
- [ ] #2 Empirical reproducer captured (real-VM run URL) demonstrating the current wedge (BOOT_MIGRATE_UP_FAILED / boot-loop / non-zero, NOT rolled_back)
- [ ] #3 Fix implemented in recovery code (King-gated — not done autonomously)
- [ ] #4 3-postswap-migrate-killed-after-commit + the migration-error scenario go GREEN (state=rolled_back) on real VMs
- [ ] #5 doc/diagrams/upgrade-timeline.plantuml + doc/upgrade-timeline.md updated to match the fixed behavior
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
<!-- SECTION:NOTES:END -->
