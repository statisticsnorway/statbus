---
id: doc-002
title: Morning summary 2026-06-09 — install-recovery overnight (LIVE)
type: other
created_date: '2026-06-08 22:08'
updated_date: '2026-06-08 23:37'
tags:
  - install-recovery
  - summary
  - overnight
  - STATBUS-017
  - NO-rollout
---
**Autonomous overnight run, night of 2026-06-08→09. LIVE doc — updated as results land; I'll give a plain-language chat brief when you wake. Run-by-run tally: STATBUS-008.**

## 🔴 HEADLINE — the rune wedge is NOT fixed (first confirmed product bug). Bears directly on the NO rollout.

The exact failure that hung the Norway box ~40h — a migration commits its schema change, then the process dies the instant before it records "done" in `db.migration` — is **not** recovered correctly. On the next boot, a "schema-skew guard" `./sb migrate up` runs **before** the recovery logic, re-runs that migration, hits "relation already exists", and **returns without restoring** → the service boot-loops. The intended "restore the snapshot, mark rolled_back, operator retries" never happens — that recovery branch is unreachable for this case.

Confirmed by **independent code-trace (architect + foreman), every link verified** (boot-migrate before recoverFromFlag at service.go:1644→:1669; `markTerminal` audit-only, no restore; inline path identical at install_upgrade.go:198; forward-recovery branch :838-927 dead). Full evidence + 3 candidate fixes: **STATBUS-017**. Empirical VM reproducer in progress (architect).

**Recommendation: HOLD the NO rollout until STATBUS-017 is fixed** — rolling out now risks repeating the wedge. Your decision; I did NOT change recovery code.

**Correction (honest):** earlier I told you the recovery handles this ("forward-once-then-restore"). It does not — the path I cited is dead code. The campaign did its job: a real bug, surfaced.

## 📊 Breadth tally: 10 / 28 green (was 5)
**Batch 1 (10 scenarios): 5 pass / 5 fail.**
- ✅ NEW GREEN: 1-boot-advisory-too-early, 1-boot-flag-stale-handoff, 3-postswap-resume-died-rollback, 3-postswap-archivebackup-watchdog, 3-postswap-worker-ddl-deadlock.
- 🔧 5 FAIL — all **first-run scenario/harness bugs** (not product), root-caused, fixes drafting now:
  - concurrent-install + migration-timeout: a harness *masking bug* hid the primary (a git-staleness abort, same class as the known coherence fix) — unmask + apply the coherence pattern.
  - between-migrations-kill: the HEAD seed collapses the upgrade delta → no "between N and N+1" point — install an older baseline.
  - startup-timeout: ran the release binary (inject is HEAD-only, no-op) — swap in the HEAD binary.
  - 4-rollback-kill: missing `fabricate_scheduled_upgrade_row` → no upgrade → the setup-kill never fired — add it.
- **Batch 2 (11: preswap + install-stage) running now** (~2h, serial). 2-preswap fixes pre-drafted; install-stage triage map ready.

## ✅ Landed
- Logging-accuracy fixes (5 sites) — pushed to master (0d18b5e30).
- Container-restart-kill rewritten to the correct rollback contract (recovery is correct; test was wrong) — committed, retest queued.

## 🔧 In progress
- **Migration-kill family**: adding the two cells you approved (kill *inside* the transaction → completed; migration *errors* → rolled_back) + diagram truth-fix marking the after-commit cell as the known bug.
- **5 Batch-1 scenario fixes** drafting; **2 preswap fixes** drafted. All retest together after Batch 2.

## 📋 Your decisions waiting
1. **STATBUS-017 — rune-wedge fix direction** (3 candidates). HIGH; gates the NO rollout.
2. **STATBUS-018 — seed pg_restore --clean fails on a populated DB** (sql_saga trigger) → silent fallback to slow full-migrations. MEDIUM; **not data-loss** (atomic), but operator-facing + a suite-wide speed/reliability hit. 4 candidate fixes.

## Tally
- Green: **10 / 28** (was 5).
- **Confirmed product bugs: 1 data-integrity-critical (STATBUS-017, rune wedge) + 1 robustness (STATBUS-018, seed --clean).**
- Harness/scenario fixes this night: container-restart-kill (done), logging (pushed), 5 Batch-1 + 2 preswap (drafted).
- 0 of the 5 Batch-1 failures were product recovery bugs — all scenario/harness first-run bugs.
