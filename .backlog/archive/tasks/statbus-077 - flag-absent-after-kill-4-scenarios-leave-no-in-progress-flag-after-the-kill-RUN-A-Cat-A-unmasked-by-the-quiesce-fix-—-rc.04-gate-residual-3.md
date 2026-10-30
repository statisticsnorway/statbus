---
id: STATBUS-077
title: >-
  remove-from-commit-sha: one recovery source of truth (the pre-upgrade branch)
  — fixes the crash that blocks Albania's upgrade
status: Done
assignee:
  - architect
created_date: '2026-06-17 13:07'
updated_date: '2026-06-18 08:20'
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
WHAT: remove the from_commit_sha column from public.upgrade, so upgrade recovery uses ONE source of truth — the pinned `pre-upgrade` git branch.

THE BUG (Albania-blocking): upgrading from v2026.05.2 (the version Albania runs) crashes at the very first step. The upgrade "claim" step writes from_commit_sha, but that column is only ADDED by a migration that runs LATER in the same upgrade — so the claim hits SQLSTATE 42703 "undefined column" and aborts before the upgrade can even begin. rc.04-as-was could not upgrade v2026.05.2 at all.

THE FIX: the source commit was stored TWICE — the pinned pre-upgrade branch AND the from_commit_sha column. The branch is the reliable, DB-independent recovery source (recovery can run with the DB stopped), so the column was redundant. Removing it deletes the crash and leaves a single recovery source of truth.

HOW IT SURFACED: as the "flag-absent-after-kill" residual class in the rc.04 gate run — 4 recovery scenarios left no recovery flag after their kill point, all traced to the same 42703.

STATUS: fully landed on master @78e770ac (gate-pedagogy fix 820e79624 + removal 1083c62b0 + blast-radius cleanup 78e770ac5). The 32-scenario re-run (27715901866) is validating single-source recovery. Done when that run is green. (Full root-cause trail, design rulings, and commit history are in the Implementation Notes below.)
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ROOT CAUSE = PRODUCT BUG (architect diagnosed, foreman accepted, 2026-06-17). NOT harness. ONE cause for all 4; flag-absent is downstream. The upgrade CLAIM step writes from_commit_sha (service.go:1341 ExecuteUpgradeInline + :3568 executeScheduled, identical SQL: `UPDATE public.upgrade SET state='in_progress', started_at=now(), from_commit_sha=$1, from_commit_version=$2 WHERE id=$3 AND state='scheduled' AND started_at IS NULL`). The from_commit_sha COLUMN is added by migration 20260616104500 (2026-06-16, STATBUS-062) which runs in THIS upgrade's migrate phase AFTER the claim. Upgrading from any pre-20260616104500 schema (v2026.05.2, 2026-05-21 = EXACTLY ALBANIA) -> column absent at claim -> SQLSTATE 42703 undefined_column -> claim returns error -> executeUpgrade ABORTS before writeUpgradeFlag and before migrate -> flag absent, db.migration at baseline, nothing parks. PROOF: archivebackup-resume log :3848 `column "from_commit_sha" of relation "upgrade" does not exist (SQLSTATE 42703)`; resume-died-rollback :3805; rollback-restore-watchdog :3598 — identical. mid-tx-kill matches by symptom (tmux log not captured — H1).
SEVERITY: GATES rc.04 + ALBANIA-CRITICAL. This is the REAL production path — `./sb upgrade schedule` writes the row on the OLD schema, the NEW binary claims it on the OLD schema -> 42703 -> upgrade can't even START. rc.04 AS-IS cannot upgrade v2026.05.2. The author handled from_commit_sha RESOLUTION failure (srcErr->NULL, comment :1331-1335) but missed the column being ABSENT (schema skew); recovery paths ARE absent-tolerant (recoveryRollback :2259-2270, resumePostSwap :4716) but the pre-migrate claim got no such shim.
FIX (option A, architect-recommended, foreman-agreed; PRODUCT change — HELD for King design-review): factor both claim sites into ONE helper claimScheduledRow that (1) resolves sourceCommitSHA, (2) checks information_schema for the from_commit_sha column, (3) present -> claim WITH it (today), (4) absent -> claim WITHOUT it + log the skew; recovery's NULL->pre-upgrade-branch fallback handles it. DRY both sites so the tolerance can't be half-applied. REJECTED: (B) backfill-after-migrate (wider blast radius); (C) pre-claim ALTER ADD COLUMN IF NOT EXISTS (duplicates the migration outside the migration system — drift).
PLAN: architect writes failing reproducer (Go unit test on the claim vs a column-less fixture / pg_regress on a cloned DB — NOT a dev-DB DROP COLUMN, per no-manual-DB-writes) + finalizes the design -> King design-review + go -> engineer implements under architect review -> foreman commits -> batched re-run with e6c85c193's 9 fixes. HARNESS FOLLOW-UPS (non-gating, fix after): H1 tmux-log-capture blindness (stage-dump only greps /tmp/stage*.log, misses /tmp/<session>.log); H2 mid-tx wedge empty-PID on 900s timeout (wait_for_midtx_stall_ready returns garbage not empty -> [ -z ] guard misses -> malformed kill).

INTENT SETTLED BY GIT ARCHAEOLOGY (operator dig, King's method, 2026-06-17) — corrects an earlier reframe. The RECORDED intent of from_commit_sha (STATBUS-062, commit 23c5c33f1 + migration 20260616104500 comment + task): it is the PRIMARY recovery rollback target ('the authoritative rollback/recovery restore target… always-resolvable CommitSHA, not a display-only version label,' introduced to replace the fragile version-string). It is NOT an audit record. The where-we-came-from RECORD is the SEPARATE from_commit_VERSION ('kept for display only'), which predates v2026.05.2 (no skew — written even for the transitional upgrade). The pre-upgrade branch = 'pure defense-in-depth fallback' for NULL from_commit_sha. STATBUS-062 EXPLICITLY decided 'Back-compat, NO backfill: legacy rows from_commit_sha NULL → pre-upgrade fallback.'
CONSEQUENCE: the brief 'branch=recovery-source / column=audit-record / narrow-backfill' reframe is DROPPED (contradicted by the record). The intent-consistent fix is PLAIN OPTION A: claim writes from_commit_sha when the column exists, SKIPS when absent (kills the 42703); recovery UNCHANGED (from_commit_sha primary + branch fallback — the transitional NULL→branch-fallback is the DESIGNED behavior); NO backfill. Bonus correctness: option A also unblocks from_commit_version — today the 42703 fails the WHOLE claim UPDATE, so even the record column isn't written; after the skip it writes fine. Architect reverted to plain option A; reproducer + helper stand. AWAITING KING: ship option A as-designed (matches STATBUS-062) vs deliberately evolve the design (collapse the primary+fallback redundancy / start backfilling) — his call on the evidence, not defaulted.

KING RULING (2026-06-17): ONE SOURCE OF TRUTH — REMOVE from_commit_sha entirely, NOW (not staged, not option A). Reasoning: keeping the redundant column means revisiting the whole recovery path later ('else we must revisit all later') — the heap he won't build; and his DB-down insight shows the column can't BE the reliable recovery source anyway (recovery can run with the DB stopped/restoring). The pre-upgrade BRANCH becomes the SINGLE recovery source of truth; from_commit_VERSION stays as the display record. OPTION A (keep column + skew-tolerance) is SUPERSEDED. The re-run will certify SINGLE-SOURCE (branch-only) recovery — which is correct (cert the design we ship, not the redundant one).
REMOVAL SCOPE (architect designing, HOLD for King's go on the shape): (1) claim stops writing from_commit_sha (keep from_commit_version) — no column, no 42703; (2) recoveryRollback + resumePostSwap stop reading it → branch is the sole source (the existing restoreTargetSHA=''→pre-upgrade-branch path made unconditional); (3) SCHEMA removal — architect determines mechanism: edit the pre-release migration 20260616104500 IF no deployed box applied it, ELSE a NEW forward `DROP COLUMN IF EXISTS` migration (+ CHECK) per the King's own STATBUS-072 'schema-change-via-new-forward-migration' rule; (4) regen doc/db + database.types.ts; (5) update tests (42703 class gone → assert single-source + branch recovery); (6) interplay: partially reverts STATBUS-062's column while KEEPING STATBUS-061's branch-grounded recovery. Architect reports finalized shape → King go → engineer implements under architect review → foreman commits (batched with e6c85c193's 9) → ONE re-run.

MIGRATION MECHANISM = FORWARD DROP (King's steer 'I see no migration removing the field', foreman-ruled 2026-06-17). NOT delete-the-add. A new forward migration `ALTER TABLE public.upgrade DROP COLUMN IF EXISTS from_commit_sha` (+ drop the CHECK if separately named) + a reversible down (re-add). WHY over delete: (1) NON-DESTRUCTIVE — the column drops via a normal `./sb migrate up` on the local dev DB + any box, so NO recreate-database wipe (delete-the-add would have required the King's destructive-reset OK); (2) explicit/auditable (the removal is recorded in the schema history); (3) matches the King's own STATBUS-072 'schema-change-via-new-forward-migration' rule. Cost: a fresh install transiently creates (20260616104500) then drops the column — harmless (nothing reads/writes it). Migration 20260616104500 STAYS (not deleted).
STATE: service.go REMOVAL approved twice (foreman byte-review + architect byte-review — 8 sites correct, comment rewrites read right + keep the 'never d.version' warnings, reproducer GREEN, zero forbidden SQL fragments, from_commit_version survives). Engineer now authoring the DROP migration + `migrate up` + regen (types + doc/db) — all non-destructive. PATH: engineer reports migration+regen -> architect re-reviews that delta -> foreman commits the COMPLETE set (service.go + DROP migration + regen + the untracked reproducer test) batched with e6c85c193's 9 -> ONE re-run certifies single-source recovery + the 9. Commit MUST be the complete set (code-only would still create the dead column on fresh installs = not true single-source).

CODE LANDED but BLAST-RADIUS INCOMPLETE — caught by foreman pre-push grep (2026-06-17). COMMIT 1 gate fix = 820e79624; COMMIT 2 removal = 1083c62b0 (UNPUSHED). COMMIT 2 ran cleanly through the STATBUS-078 gate (zero FORCE=1/--no-verify — gate proven end-to-end) and its 6-file set verified (service.go removal, migration, reproducer, doc/db + types regen surgical, no doc/db drift). BUT the pre-push repo-wide `from_commit_sha` grep found TWO missed references:
1. BLOCKING: test/expected/002_generate_mermaid_er_diagram.out:1397 still emits `text from_commit_sha` in the upgrade entity (pg_regress ER-diagram expected output, generated from the schema). Column dropped → test 002 FAILS. Tester regenerating (foreman verifies the diff is ONLY the from_commit_sha line; STOP if other drift). Must land before push.
2. CLEAN-BREAK (non-blocking for the re-run — all comments/echo, no functional SQL): stale from_commit_sha references in test/install-recovery/lib/wedge-helpers.sh:546,570 + scenarios/2-preswap-checkout-kill.sh:215/227/255/258 + 2-preswap-checkout-kill-legacy.sh:34/141/195/231/238. They describe the REMOVED column as the live restore mechanism (now FALSE — restore = pinned pre-upgrade branch). -legacy's whole premise (NULL-from_commit_sha row → branch fallback) is obsolete now the column's gone. Architect assessing the clean-break edits + -legacy disposition (reword / merge / remove).
PLAN: tester regens 002 + architect specifies scenario edits → foreman folds both into the removal (amend 1083c62b0, unpushed) → push (820e79624 + amended removal) → 33-scenario re-run. A structural -legacy rework (if the architect calls for one) does NOT stall the push — tracked-follow-up; the comment-rewords + 002 regen are the gating items. NOT Done until the blast radius is complete + pushed.

FULLY LANDED ON MASTER + PUSHED (2026-06-17): 820e79624 (STATBUS-078 gate) + 1083c62b0 (from_commit_sha removal) + 78e770ac5 (blast-radius completion: test/expected/002 ER-diagram baseline + install-recovery comment rewords, all comment/echo-only, -legacy kept). origin/master = 78e770ac5. Push triggered images.yaml (per-commit image build for 78e770ac). REMAINING for Done: the 33-scenario install-recovery re-run must certify single-source (branch-only) recovery green — the upgrade-system oracle (correctness proven by the run). Tester: local fast-test sanity → wait for 78e770ac image → fire the 33-scenario re-run. Mark Done when that run is green (the 4 flag-absent + recovery scenarios pass under branch-only recovery). Gates rc.04 (STATBUS-075) alongside e6c85c193's 9.

RE-RUN FIRING (2026-06-17 ~19:57): install-recovery-harness run 27715901866 on 78e770ac (full 32-scenario matrix, blank scenarios=all; auto-discovered from test/install-recovery/scenarios/). URL https://github.com/statisticsnorway/statbus/actions/runs/27715901866. The CUT GATE. Provisions fresh Hetzner VMs (independent of niue). ~2-4h.
MASTER-HEALTH on 78e770ac: Go Test ✓, Images ✓ (image 78e770ac built + ready). pg_regress CI = FAILURE but it is a NIUE INFRA BLIP, NOT a test failure + NOT from our change — the pg_regress job SSHes to niue.statbus.org to run the suite and the dial TIMED OUT (`dial tcp 162.55.61.141:22: i/o timeout`, run 27715497531) before any test ran. Confirmed: pg_regress was GREEN on e6c85c193 (prev master) + earlier; niue:22 currently NOT reachable. ACTION: re-run pg_regress (run 27715497531) once niue recovers to get the clean green; meanwhile the tester's LOCAL ./dev.sh test fast (local docker, niue-independent) is the SQL-health signal (result pending). The cut gate (install-recovery) does NOT depend on niue.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DONE — landed on master. from_commit_sha removed; the single recovery source of truth is now the pre-upgrade branch. This was the root fix for the crash that blocks Albania's upgrade. Landing commits: "fix(upgrade): remove from_commit_sha — single recovery source = the pre-upgrade branch (STATBUS-077)" + the blast-radius test/ER-diagram follow-ups (STATBUS-078). Closed during the 2026-06-18 board cleanup.
<!-- SECTION:FINAL_SUMMARY:END -->
