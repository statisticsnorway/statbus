---
id: STATBUS-051
title: >-
  install-log-honesty: kill the structural A17 false-alarm (keep real-misuse
  detection) + honest post-upgrade-fixup banner & flag-name + symmetric
  completion logging [047 item C]
status: Done
assignee:
  - architect
created_date: '2026-06-15 10:04'
updated_date: '2026-06-15 10:27'
labels:
  - upgrade
  - install
  - install-log-honesty
dependencies: []
references:
  - tmp/architect-047C-two-pass-flag-lifecycle.md
  - cli/cmd/install.go
  - cli/internal/upgrade/exec.go
  - cli/internal/upgrade/service.go
  - doc/upgrade-timeline.md
priority: high
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From STATBUS-047 item C (rune install-log review). King decision 2026-06-15: FIX ALL, PRINCIPLED — no half-measures, no open questions routed back. Architect diagnosis (foreman-verified end-to-end): tmp/architect-047C-two-pass-flag-lifecycle.md. ALL fixes are Go logging/control-flow + a doc note + an internal rename — NO migration, no schema/proc change.

## Root cause (verified)
The post-upgrade install fixup re-runs `./sb install` once after every upgrade to apply new infra idempotently. "rune-stuck-fix A" moved the terminal state='completed' UPDATE + removeUpgradeFlag() (service.go:4453) to run BEFORE runInstallFixup (service.go:4524, its only call site; guarded by ground_truth_test.go:356-371). The fixup child is the ONLY caller that sets the bypass signal (--inside-active-upgrade + STATBUS_INSIDE_ACTIVE_UPGRADE=1, exec.go:91/96 — grep-confirmed no other setter), and it always runs after the flag is gone. acquireOrBypass (install.go:178-192) is "flag present → honored; absent → A17", no other condition → A17 ("INVARIANT … violated") fires on EVERY upgrade. Structurally-guaranteed false positive: harmless (proceeds) but cry-wolf in the invariant channel, so a real A-series violation would be distrusted. The exec.go:82-83 comment ("our own flag is still on disk at this point") is now FALSE (predates fix A).

## The four fixes (all principled — decisions already resolved, no forks)
1. **Silence the false alarm honestly, KEEP real detection.** In acquireOrBypass (install.go:180-192), when no flag is found, branch on the fixup-child signature (the env var STATBUS_INSIDE_ACTIVE_UPGRADE=1, set only by runInstallFixup): env var present → EXPECTED, log a calm info line ("post-upgrade fixup: upgrade already completed and cleared its flag — proceeding (expected)"), NOT "INVARIANT … violated". Env var absent (someone hand-passed the bare internal flag) → KEEP the actionable misuse warning. Correct the stale exec.go:82-83 comment to the post-fix-A truth (flag already removed by applyPostSwap; bypass tells the child to skip detection/row-authoring and not expect a flag). Optionally tighten the applyPostSwap comment (service.go:4516-4521) to name the bypass as load-bearing (suppresses a duplicate row + redundant install-log, not just audit).
2. **Rename the lying internal flag.** --inside-active-upgrade + STATBUS_INSIDE_ACTIVE_UPGRADE now misname the state: the upgrade is COMPLETE, not active, when the fixup runs. Rename both to an honest post-completion-fixup semantic across ALL call sites (clean break — the flag is hidden/internal, set only by the service on its own child; service.go:594 explicitly tells operators never to pass it, so there is NO external contract). Sites: install.go (var ~93, flag def ~142, MarkHidden ~145, readers ~183/188/260/1722/1763), exec.go (91/96), service.go (594/3469/4394/4519 + the bypass docs), inject.go:55, and the guard tests (install_test.go, unit_reconcile_test.go) — update strings + identifiers together, no shim.
3. **Self-identify the fixup banner.** The fixup child prints the same bare "StatBus Installation" / "====" banner as a fresh top-level install (install.go:225-226), which is what reads as a second independent install going wrong. When bypass (fixup child), print a distinct banner, e.g. "StatBus Post-Upgrade Install Fixup". ~2 lines, no behavior change. Do NOT unify the passes — the fixup child is a legitimately separate process (pid differs; the two rows 187-healed + 196-recorded are correct-by-design).
4. **Symmetric completion logging + doc the two-row model.** Row 187 (recovery-completed) gets the rich logUpgradeRow[completed-normal] dump (service.go:4452); row 196 (install-recorded) gets only a terse fmt.Printf (install.go:1947) though completeInstallUpgradeRow holds the same fields. Add RETURNING row_to_json(upgrade) to that INSERT (mirroring upgradeRowReturning at applyPostSwap:4409) and call logUpgradeRow with a NEW label LabelCompletedInstall = "completed-install" (define alongside service.go:1346). Add a short note to doc/upgrade-timeline.md on the two-row model: recovery completes the prior in-flight upgrade as its own row; install records the running version as a separate completed row — both intended; labels distinguish them.

## Why not just move the fixup before flag-removal
That reintroduces rune-stuck-fix-A's bug (the fixup restarts docker/db, RST-ing the parent's pgx conn before the completed UPDATE lands). Out — and guarded by ground_truth_test.go:356-371.

## Precision note (corrects the original review framing)
#196 is authored by pass-1's post-recovery continuation (install.go:1947, no-install.log L4142), NOT the fixup child (bypass=true authors nothing; install.go:486 gates the completion-defer on !bypass). The terse line just appears after the L4056 fixup banner because pass-1 resumes once the nested child returns.

## Constraints / DoD
- NO migration. Go logging/control-flow + the internal rename + a doc note only.
- Coordination caveat from the diagnosis is MOOT: STATBUS-033 (cd923c3b4) is committed, so the install.go classifier region is settled — the C3 log-line + RETURNING addition at ~install.go:1947 won't collide.
- go -C cli vet/build/test green (the per-change go-test gate runs on push). Update the guard tests that assert on the renamed flag strings.
- do-not-self-commit: leave it uncommitted, report to the foreman with the diff + tests for byte-level review + commit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A17 false-alarm no longer fires for the post-upgrade fixup: env-var-recognized fixup child logs a calm EXPECTED line (no 'INVARIANT … violated'); a hand-passed bare internal flag still emits the actionable misuse warning; stale exec.go:82-83 comment corrected
- [x] #2 The internal --inside-active-upgrade flag + STATBUS_INSIDE_ACTIVE_UPGRADE env var renamed to an honest post-completion-fixup semantic across ALL call sites + guard tests (clean break, no shim; no external contract since the flag is hidden/internal)
- [x] #3 The fixup child's install banner is self-identifying (distinct from the bare 'StatBus Installation'); the two passes are NOT unified
- [x] #4 Install-recorded completion row emits a structured logUpgradeRow dump under a new 'completed-install' label, symmetric with the recovery-completed row; the two-row model is documented in doc/upgrade-timeline.md
- [x] #5 NO migration; go vet/build/test green (incl. updated guard tests); foreman byte-level reviewed + committed (do-not-self-commit)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ARCHITECT IMPLEMENTATION COMPLETE (2026-06-15, Opus 4.8) — staged, NOT committed (foreman byte-level review + commit; do-not-self-commit). 9 files staged, go build/vet/test ALL GREEN (full cli suite: 0 FAIL across 10 packages; cmd + internal/upgrade re-run clean).

NAMES CHOSEN (honest post-completion semantic): --inside-active-upgrade → --post-upgrade-fixup ; STATBUS_INSIDE_ACTIVE_UPGRADE → STATBUS_POST_UPGRADE_FIXUP ; insideActiveUpgrade → postUpgradeFixup. Clean break, no shim. ZERO residual old tokens anywhere in the repo (whole-repo rg sweep).

PART 1 (A17): acquireOrBypass (install.go) now three-way — flag present → bypass honored; flag absent + STATBUS_POST_UPGRADE_FIXUP=1 → calm EXPECTED line (no INVARIANT); flag absent + NO env signature → A17 kept, reworded as genuine hand-passed-flag misuse. Registry ViolationShape (install.go) narrowed to match. Stale exec.go runInstallFixup comment rewritten to post-fix-A truth. applyPostSwap comment (service.go) corrected to name the bypass LOAD-BEARING (suppresses dup row + DB probe + log), not just audit. DECISION (no fork): kept A17 as the named invariant narrowed to misuse-only (no test pinned A17; preserves the named-audit discipline while killing the structural false positive).

PART 2 (rename): all call sites + guard tests + comments across install.go, install_test.go, unit_reconcile_test.go, inject.go, exec.go, service.go + 2 docs + 1 install-recovery scenario. Test func TestRunInstallService_GatesNowOnInsideActiveUpgrade → ...OnPostUpgradeFixup (+ its cross-ref). Guard tests assert the renamed gate strings and pass.

PART 3 (banner): runInstall prints 'StatBus Post-Upgrade Install Fixup' when bypass, else 'StatBus Installation'. bypass hoisted to top of runInstall (computed once; banner + mutex section agree). Passes NOT unified.

PART 4 (symmetric logging): completeInstallUpgradeRow (install.go) Exec→QueryRow with RETURNING to_jsonb(upgrade.*); logs `upgrade row [completed-install] <json>` (same format as logUpgradeRow → journald grep contract holds). New label LabelCompletedInstall='completed-install' (service.go). ErrNoRows (ON CONFLICT no-op when already completed) handled as benign idempotent re-run (added "errors" import). doc/upgrade-timeline.md: FIXED a stale step-13/14 ORDERING (it had fixup BEFORE mark-completed/removeUpgradeFlag — same pre-fix-A falsehood as the code comments) + added the two-row-model subsection + updated the bypass decision-tree and signals section.

NO migration. claude-team.zip (untracked) is NOT mine — left alone. Diff: git -C /Users/jhf/ssb/statbus diff --staged
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SHIPPED — commit 4546cfbc4 (master, pushed; per-change go-test gate runs on push). Architect implemented (do-not-self-commit); foreman byte-level reviewed + independently re-ran vet/build/FULL suite (10 packages, 0 fail) + committed. 9 files, +175/-77.

PROBLEM (047 item C): the "INVARIANT A17 violated" line is a STRUCTURALLY-GUARANTEED FALSE POSITIVE firing on EVERY upgrade (root cause foreman-verified end-to-end); plus two-banner confusion + dual-row logging asymmetry.

FIX (all Go logging/control-flow/naming + doc note; NO migration):
1. acquireOrBypass now THREE-WAY: flag present → bypass honored; flag absent + STATBUS_POST_UPGRADE_FIXUP=1 env signature (set only by the fixup child) → EXPECTED, calm line, no invariant; flag absent + no env → A17 KEPT, narrowed + reworded to the one genuine case (a bare --post-upgrade-fixup hand-passed by an operator). Registry ViolationShape narrowed. Stale exec.go comment rewritten to post-fix-A truth; applyPostSwap comment corrected to name the bypass LOAD-BEARING (suppresses a duplicate row + DB probe + log).
2. RENAME (clean break, no shim — flag is hidden/internal, no external contract): --inside-active-upgrade / STATBUS_INSIDE_ACTIVE_UPGRADE / insideActiveUpgrade → --post-upgrade-fixup / STATBUS_POST_UPGRADE_FIXUP / postUpgradeFixup across every call site + guard tests + 2 docs + 1 install-recovery scenario. Whole-repo sweep = ZERO residual old tokens (foreman-verified). The critical env-var handshake is consistent: setter exec.go:100 == readers install.go:196/242.
3. Self-identifying banner: "StatBus Post-Upgrade Install Fixup" when bypass (else the bare "StatBus Installation"); bypass hoisted to the top of runInstall (computed once; banner + mutex agree); passes NOT unified.
4. Symmetric completion logging: completeInstallUpgradeRow Exec→QueryRow + RETURNING to_jsonb(upgrade.*) → "upgrade row [completed-install] <json>" (new LabelCompletedInstall), same greppable format as the recovery path's logUpgradeRow[completed-normal]. pgx.ErrNoRows (idempotent re-install of an already-completed version → ON CONFLICT no-op → no row returned) handled as benign WITHOUT masking real errors (those still hit the A9 path). doc/upgrade-timeline.md gains a two-row-model section + corrected step ordering (complete+flag-removal BEFORE the fixup).

BONUS (architect catch): doc/upgrade-timeline.md had the SAME stale ordering bug as the old code comments (listed fixup before mark-completed) — fixed to match the code.

DESIGN CALL (foreman-affirmed, principled — NOT routed to the King as it aligns with his keep-detection decision): A17 kept as a NARROWED named invariant (genuine misuse only) rather than retired to a plain warning — preserves the A-series named-audit discipline + real detection while killing the structural false positive.

VERIFY: foreman byte-level review (3-way branch logic; env-var handshake setter==reader; ErrNoRows discrimination; banner; doc ordering vs code); go vet + build + full cli test suite green (10 packages, 0 fail; the structural guard tests assert the renamed gate strings + pass). NO migration.
<!-- SECTION:FINAL_SUMMARY:END -->
