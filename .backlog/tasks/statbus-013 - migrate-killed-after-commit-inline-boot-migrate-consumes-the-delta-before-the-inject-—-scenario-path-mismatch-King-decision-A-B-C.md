---
id: STATBUS-013
title: >-
  migrate-killed-after-commit: inline boot-migrate consumes the delta before the
  inject — scenario/path mismatch (King decision A/B/C)
status: Done
assignee: []
created_date: '2026-06-08 01:53'
updated_date: '2026-07-06 15:59'
labels:
  - install-recovery
  - upgrade
  - recovery
dependencies: []
references:
  - test/install-recovery/scenarios/3-postswap-migrate-killed-after-commit.sh
  - cli/internal/install/install_upgrade.go
  - cli/internal/upgrade/service.go
priority: high
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DECISIVELY DIAGNOSED in the overnight grind (engineer, from run 27109532127 stage1 log + code). migrate-killed-after-commit never fires its stall because of a STRUCTURAL mismatch between the scenario's injection model and the inline dispatch path it actually exercises.

ROOT CAUSE:
- The scenario uses INLINE `./sb install` dispatch. The inline post-swap handoff is syscall.Exec → re-exec'd `./sb install` → install.Detect = crashed-upgrade (EXPECTED — the flock is O_CLOEXEC, released on exec; NOT a crash) → runCrashRecovery (install_upgrade.go:131) → a BOOT-migrate (install_upgrade.go:198, "schema-skew guard: bring schema to HEAD") THEN RecoverFromFlag → resumePostSwap → the resume-migrate.
- The BOOT-migrate consumes the ENTIRE v2026.05.2→HEAD migration delta. By the time the resume-migrate (the scenario's intended inject target, migrate.go:829 stall) runs, db.migration is already at HEAD → no delta → no stall there.
- AND the inject env (STATBUS_INJECT_AT + the release-file var) is ABSENT in the boot-migrate — so it doesn't stall there either. Evidence: the boot-migrate progressed to the ~10th delta migration (20260530212300) without stalling; the first delta migration is 20260520204526; inject.Validate (inject.go:326-330) would have REJECTED a stall-class with no release file at startup, but the boot-migrate ran fine → both env vars absent, not misconfigured. Lost at/before syscall.Exec (service.go:3604); no explicit env-scrub found → subtle propagation gap across the inline re-exec → crash-recovery → boot-migrate chain.
- (The 900s timeout caught the boot-migrate mid-flight, also slowed by a flaky crash-recovery DB-bring-up: "DB not ready: /var/run/postgresql:5432 - no response".)

WHY SERVICE-DISPATCH SCENARIOS WORK: watchdog-reconnect / archivebackup-watchdog resume via NOTIFY → the service's recoverFromFlag → resumePostSwap directly — NO crash-recovery boot-migrate. So those align run-path with injection-model; migrate-killed-after-commit does not.

CANDIDATE FIXES (King/architect decision — each non-trivial):
A. Switch this scenario to SERVICE dispatch (NOTIFY, like watchdog-reconnect) → resume via resumePostSwap with no crash-recovery boot-migrate; aligns the path with the injection model. Engineer leans A. BUT reverses the scenario's inline-dispatch design + drops inline-path coverage.
B. Fix the inject-env propagation across the inline syscall.Exec → crash-recovery → boot-migrate. NOTE: STATBUS_INJECT_AT is test-only, so this matters for the test — BUT the real question is whether ANY production env vars must survive that handoff; if so, it's a genuine product bug worth fixing regardless.
C. Accept the boot-migrate as the inject target (keeps inline-path coverage) + fix the env propagation (B) AND the crash-recovery DB-bring-up fragility so the stall is reached + detected there.

TRADE-OFF: A is simplest but tests the service path (which watchdog-reconnect already covers); C keeps the unique inline-path coverage but needs B + a DB-fragility fix. The inline crash-recovery path (./sb install resuming a crashed upgrade with a boot-migrate) is a REAL operator recovery path worth testing — so dropping its coverage (A) has a cost.

CROSS-CHECK PENDING: 3-postswap-mid-migration-kill (KILL at migrate.go:387, fires BEFORE a migration) is running. If it ALSO fails to fire → the inject-env loss is a shared inline-path gap. If it PASSES → the env DID reach its boot-migrate, localizing the loss. (Update this task with the result.)

NOT an autonomous overnight fix — it reverses scenario design / touches recovery semantics. Full diagnosis chain in the engineer's report (this task) + STATBUS-008 notes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 King/architect decides A vs B vs C (path-alignment vs inline-coverage vs env-fix)
- [ ] #2 If B/C chosen: determine whether the inline syscall.Exec env-loss affects any PRODUCTION env vars (real product bug) vs test-only
- [ ] #3 migrate-killed-after-commit driven to GREEN on the chosen approach
- [x] #4 mid-migration-kill cross-check result folded in (shared gap vs localized)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CROSS-CHECK RESULT: 3-postswap-mid-migration-kill PASSED (runs 27111249171 + 27111797569). mid-migration-kill is ALSO inline (checkout HEAD + pre-stage) and its KILL inject (migrate.go:387, before a migration) FIRED in the inline boot-migrate — so the inline inject-env DOES reach the boot-migrate. Therefore the env-propagation is NOT universally broken; migrate-killed-after-commit's STALL-not-firing is LOCALIZED. This sharpens the candidates: the issue is specific to the STALL inject (which needs STATBUS_INJECT_STALL_UNTIL_REMOVED_FILE — the release-file var may not propagate while STATBUS_INJECT_AT does), OR the boot-migrate flies through all migrations because the STALL (after-commit, migrate.go:829) release-file isn't present/effective there. Net for the A/B/C decision: option B (env-propagation) narrows to the STALL release-file var specifically; the boot-migrate-consumes-delta structural point still stands. (Engineer can pin the exact release-file-propagation detail when the King picks a direction.)

=== THE FAILURE MODE = THE SPEC (how it SHOULD work) — confirmed verbatim with the King 2026-06-08 ===

WHAT PHYSICALLY FAILS (the 'rune wedge', physically hit on the rune/Norway box):
1. A migration runs and COMMITS its change to the DB — e.g. it creates a table; that table now exists and is permanent.
2. The migrator's very next step is to write a bookkeeping row into db.migration recording 'this migration is done.'
3. The crash is injected IN THE GAP between (1) and (2): the schema change is live, but the db.migration row was NEVER written (the process is gone before it gets there — it doesn't 'fail', it never happens). Inject point: migrate-subprocess-killed-after-commit-before-recorded.

WHAT THE PRODUCT SHOULD DO ON RESTART (the correct recovery):
4. It detects the upgrade was interrupted and resumes.
5. It re-runs migrations and checks db.migration for what's left. The killed migration ISN'T recorded → looks un-applied → it tries to run it again.
6. The re-run hits the already-existing object → Postgres 'relation already exists' → the migration can't apply.
7. The product has NO safe way to reconcile a half-applied-but-unrecorded migration, so it RESTORES the DB from the pre-upgrade backup and marks the upgrade rolled_back.
8. End state: cleanly back on the OLD version, consistent, operator can simply retry.

THE SPEC IN ONE LINE: the crash leaves schema and bookkeeping out of sync; the CORRECT product response is 'don't try to be clever about a half-applied state — restore to the known-good snapshot' → rolled_back.

=== DECISION (North Star evaluation, King 2026-06-08): OPTION A — SERVICE DISPATCH (AC#1 done) ===
North Star = a working UNATTENDED install; the diagram shows what can fail; we TEST the things that can PHYSICALLY fail.
- The wedge is at the MIGRATE STEP and is DISPATCH-AGNOSTIC (same step whether the systemd service or ./sb install started the upgrade).
- A (service dispatch): tests the wedge on the REAL production upgrade path (systemd service → applyPostSwap → migrate → kill-in-window → resume → wedge → restore), exactly where the diagram marks it, no test scaffolding bent. = THE NORTH STAR. CHOSEN.
- B (fix inline env-propagation): REJECTED — fixes TEST PLUMBING (STATBUS_INJECT_AT surviving syscall.Exec; production has no inject env) to reach a second-order context (the inline recovery-install's boot-migrate). Tests the rig, not a physical failure.
- C (boot-migrate target + env + DB-fragility): REJECTED — B + more scaffolding.
- 'A drops inline coverage' objection does NOT hold: the inline boot-migrate is the SAME failure mode on a messier path; mid-migration-kill (GREEN) already exercises the inline migrate-kill; the inline path's distinct risk (the binary-swap handoff) is its own scenario. No distinct physical failure lost.
- SEPARATE latent question (own task, NOT this): does the inline syscall.Exec lose any PRODUCTION env vars (not the test one)? If yes = a real product bug — quick check.

=== NEXT STEP (King 2026-06-08): VERIFY THE DIAGRAM matches this spec ===
The spec above is HOW IT SHOULD BE. Next we must verify the DIAGRAM actually shows it: check doc/diagrams/upgrade-timeline.plantuml + the TEST note for migrate-killed-after-commit — does it show migrate step → kill in the commit↔record window → re-run → 'relation already exists' → restore-from-backup → rolled_back, on the SERVICE-dispatch path (Option A)? Fix the diagram if wrong/missing. This closes the loop: the diagram shows what can fail → we test what physically fails. THEN implement A (rewrite migrate-killed-after-commit to service dispatch like watchdog-reconnect).

RECLASSIFIED 2026-06-11 (architect Fable + foreman-verified): NOT King-blocked. The King DECIDED Option A (service dispatch) on 2026-06-08 (AC#1 checked; see the DECISION block above). The 'separate latent question' (does the inline syscall.Exec lose any PRODUCTION env vars?) is now ANSWERED: NO — service.go:3624 passes os.Args + os.Environ() VERBATIM (foreman-verified). Only the test-only STALL release-file var was scenario plumbing. So 013 = TEST-ONLY artifact; remaining work is HARNESS: rewrite migrate-killed-after-commit to service dispatch (AC#3) + verify/close the diagram per the King's 6/8 next-step. Removed the needs-king-decision label. NOTE: 013's structural finding (boot-migrate consumes the whole delta) is the empirical corroboration of STATBUS-012's severity.

FOLD (architect, 2026-06-21, King-approved consolidation): the after-commit-before-recorded window this scenario targets is a NON-PROBLEM — the rollback is the recovery. See STATBUS-097 (resolved) + tmp/architect-097-understanding.md. The committed-but-unrecorded state self-corrects: recovery re-runs → conflict → rollback → re-apply fresh → completed (idempotent migrations recover forward, no rollback). So this scenario exercises a state the system already handles correctly. Reconsider this item's A/B/C (fix the test so the inject fires) in that light: the scenario should most likely be reframed to assert `completed` or retired — same disposition as STATBUS-105's held arcs — rather than re-engineered to exercise a non-problem. To confirm with the King in the backlog review.

RETRACTION (architect, 2026-06-21) — DISREGARD the FOLD note immediately above; it was WRONG and I caught it minutes later. 013's verbatim King spec STANDS: the correct terminal is ROLLED_BACK (restore to known-good → operator retries), NOT completed. The recent STATBUS-097/105 'completed is correct' framing INVERTED this task's ground-truth; the foreman + architect caught it before it was cemented. The fold note's 'reframe to completed' is void. All 097/105/013 consolidation is HELD for the King's ticket-clarity reset. The box reaching 'completed' (overnight) is the DEVIATION from this spec — possibly the real gap — not a non-problem.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MERGED into STATBUS-105 (spec+verify) and STATBUS-071 (the arc): the rolled_back spec is NOT superseded — it moves to 105 as its canonical spec+verify home (which owns the open measurement), and 071's coverage map asserts it. What's dead is 013's own mechanics: the inject/env analysis + the old fabricated scenario, which predate the boot-migrate reality (STATBUS-044 comments #5–#6) and the budget hoist (cc660280f).
<!-- SECTION:FINAL_SUMMARY:END -->
