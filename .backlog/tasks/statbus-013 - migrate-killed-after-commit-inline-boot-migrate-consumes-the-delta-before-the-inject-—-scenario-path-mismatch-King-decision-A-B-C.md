---
id: STATBUS-013
title: >-
  migrate-killed-after-commit: inline boot-migrate consumes the delta before the
  inject — scenario/path mismatch (King decision A/B/C)
status: To Do
assignee: []
created_date: '2026-06-08 01:53'
labels:
  - install-recovery
  - upgrade
  - recovery
  - needs-king-decision
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
- [ ] #1 King/architect decides A vs B vs C (path-alignment vs inline-coverage vs env-fix)
- [ ] #2 If B/C chosen: determine whether the inline syscall.Exec env-loss affects any PRODUCTION env vars (real product bug) vs test-only
- [ ] #3 migrate-killed-after-commit driven to GREEN on the chosen approach
- [ ] #4 mid-migration-kill cross-check result folded in (shared gap vs localized)
<!-- AC:END -->
