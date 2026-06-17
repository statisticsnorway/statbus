---
id: STATBUS-077
title: >-
  flag-absent-after-kill: 4 scenarios leave no in-progress flag after the kill
  (RUN-A Cat A unmasked by the quiesce fix) — rc.04 gate residual #3
status: In Progress
assignee:
  - architect
created_date: '2026-06-17 13:07'
updated_date: '2026-06-17 15:38'
labels:
  - install-recovery
  - rc.04
  - gate
  - recovery
  - flag-timing
  - regression-triage
dependencies:
  - STATBUS-075
references:
  - cli/internal/upgrade/service.go
  - cli/cmd/install_upgrade.go
  - test/install-recovery/scenarios/3-postswap-mid-tx-kill.sh
  - test/install-recovery/scenarios/3-postswap-resume-died-rollback.sh
priority: high
ordinal: 77000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE genuinely-new 3rd residual class from run 27683157288 (commit 3a0d6e6dd) — surfaced once the SIGKILL-quiesce fix (3a0d6e6dd) removed the quiesce-rollback that previously MASKED it (this was RUN A's "Category A: flag absent after kill"). NOT fixed by e6c85c193 (which fixes only freshness + masked-unit).

THE 4 SCENARIOS (all fail `✗ expected flag file present after kill`): 3-postswap-archivebackup-resume, 3-postswap-mid-tx-kill, 3-postswap-resume-died-rollback, 4-rollback-restore-watchdog. All have a coherent fabricate (HEAD,HEAD) → the install reaches its kill point → after the kill the upgrade-in-progress flag file is ABSENT.

THE QUESTION (architect diagnosing, first principles, product-vs-harness):
(a) PRODUCT bug: executeUpgrade does not write the in-progress flag BEFORE the kill point → a crash there leaves NO recovery marker. If so this is ALBANIA-CRITICAL: a mid-upgrade crash on a no-remote-rescue standalone box would be undetectable by recovery (the operator's re-run couldn't find the interrupted upgrade). This is the exact class the campaign exists to harden.
(b) HARNESS bug: the kill/park misfired or the assertion checks too early. CLUE: mid-tx-kill's log shows `migrate subprocess parked (PID=          )` — park-detection captured an EMPTY PID before pg_terminate_backend, so the kill may not have fired at the intended mid-tx point.

OPEN: do the 4 kill at the same conceptual point or different (mid-tx / mid-applyPostSwap / resume-died / rollback-restore)? One root cause or several? Per-scenario logs in tmp/run288/cls-<scenario>/.

GATING: blocks the rc.04 100%-green gate (STATBUS-075) alongside the (already-fixed) freshness + masked-unit classes. The re-run is HELD until this fix lands so it batches with e6c85c193's 9 fixes into ONE comprehensive re-run. OWNER: architect (diagnose product-vs-harness + fix shape) -> implement -> foreman review/commit -> re-run.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ROOT CAUSE = PRODUCT BUG (architect diagnosed, foreman accepted, 2026-06-17). NOT harness. ONE cause for all 4; flag-absent is downstream. The upgrade CLAIM step writes from_commit_sha (service.go:1341 ExecuteUpgradeInline + :3568 executeScheduled, identical SQL: `UPDATE public.upgrade SET state='in_progress', started_at=now(), from_commit_sha=$1, from_commit_version=$2 WHERE id=$3 AND state='scheduled' AND started_at IS NULL`). The from_commit_sha COLUMN is added by migration 20260616104500 (2026-06-16, STATBUS-062) which runs in THIS upgrade's migrate phase AFTER the claim. Upgrading from any pre-20260616104500 schema (v2026.05.2, 2026-05-21 = EXACTLY ALBANIA) -> column absent at claim -> SQLSTATE 42703 undefined_column -> claim returns error -> executeUpgrade ABORTS before writeUpgradeFlag and before migrate -> flag absent, db.migration at baseline, nothing parks. PROOF: archivebackup-resume log :3848 `column "from_commit_sha" of relation "upgrade" does not exist (SQLSTATE 42703)`; resume-died-rollback :3805; rollback-restore-watchdog :3598 — identical. mid-tx-kill matches by symptom (tmux log not captured — H1).
SEVERITY: GATES rc.04 + ALBANIA-CRITICAL. This is the REAL production path — `./sb upgrade schedule` writes the row on the OLD schema, the NEW binary claims it on the OLD schema -> 42703 -> upgrade can't even START. rc.04 AS-IS cannot upgrade v2026.05.2. The author handled from_commit_sha RESOLUTION failure (srcErr->NULL, comment :1331-1335) but missed the column being ABSENT (schema skew); recovery paths ARE absent-tolerant (recoveryRollback :2259-2270, resumePostSwap :4716) but the pre-migrate claim got no such shim.
FIX (option A, architect-recommended, foreman-agreed; PRODUCT change — HELD for King design-review): factor both claim sites into ONE helper claimScheduledRow that (1) resolves sourceCommitSHA, (2) checks information_schema for the from_commit_sha column, (3) present -> claim WITH it (today), (4) absent -> claim WITHOUT it + log the skew; recovery's NULL->pre-upgrade-branch fallback handles it. DRY both sites so the tolerance can't be half-applied. REJECTED: (B) backfill-after-migrate (wider blast radius); (C) pre-claim ALTER ADD COLUMN IF NOT EXISTS (duplicates the migration outside the migration system — drift).
PLAN: architect writes failing reproducer (Go unit test on the claim vs a column-less fixture / pg_regress on a cloned DB — NOT a dev-DB DROP COLUMN, per no-manual-DB-writes) + finalizes the design -> King design-review + go -> engineer implements under architect review -> foreman commits -> batched re-run with e6c85c193's 9 fixes. HARNESS FOLLOW-UPS (non-gating, fix after): H1 tmux-log-capture blindness (stage-dump only greps /tmp/stage*.log, misses /tmp/<session>.log); H2 mid-tx wedge empty-PID on 900s timeout (wait_for_midtx_stall_ready returns garbage not empty -> [ -z ] guard misses -> malformed kill).

INTENT SETTLED BY GIT ARCHAEOLOGY (operator dig, King's method, 2026-06-17) — corrects an earlier reframe. The RECORDED intent of from_commit_sha (STATBUS-062, commit 23c5c33f1 + migration 20260616104500 comment + task): it is the PRIMARY recovery rollback target ('the authoritative rollback/recovery restore target… always-resolvable CommitSHA, not a display-only version label,' introduced to replace the fragile version-string). It is NOT an audit record. The where-we-came-from RECORD is the SEPARATE from_commit_VERSION ('kept for display only'), which predates v2026.05.2 (no skew — written even for the transitional upgrade). The pre-upgrade branch = 'pure defense-in-depth fallback' for NULL from_commit_sha. STATBUS-062 EXPLICITLY decided 'Back-compat, NO backfill: legacy rows from_commit_sha NULL → pre-upgrade fallback.'
CONSEQUENCE: the brief 'branch=recovery-source / column=audit-record / narrow-backfill' reframe is DROPPED (contradicted by the record). The intent-consistent fix is PLAIN OPTION A: claim writes from_commit_sha when the column exists, SKIPS when absent (kills the 42703); recovery UNCHANGED (from_commit_sha primary + branch fallback — the transitional NULL→branch-fallback is the DESIGNED behavior); NO backfill. Bonus correctness: option A also unblocks from_commit_version — today the 42703 fails the WHOLE claim UPDATE, so even the record column isn't written; after the skip it writes fine. Architect reverted to plain option A; reproducer + helper stand. AWAITING KING: ship option A as-designed (matches STATBUS-062) vs deliberately evolve the design (collapse the primary+fallback redundancy / start backfilling) — his call on the evidence, not defaulted.
<!-- SECTION:NOTES:END -->
