---
id: doc-017
title: >-
  STATBUS-071 §9(5) 5d — CAT-C design-pass (mid-migrate mechanisms + worker-ddl
  + matrix)
type: specification
created_date: '2026-06-19 11:40'
---
# STATBUS-071 §9(5) 5d — CAT-C design-pass

**Audience:** engineer (build after CAT-B closes) + foreman (review/commit/VM-prove). **Architect design-pass, 2026-06-19.** Companion to doc-016.

## 0. CORRECTION to doc-016 (own it)
doc-016 marked :388/:911 as "ride 5a (structure+review, no interim VM)". **WRONG** — the engineer's pre-read is right. 5a proved the KillHere→**rollback** path (PreSwap recoveryRollback). :388/:911 are a DISTINCT mechanism: **ONE-SHOT KillHere → forward-recovery → COMPLETED** (not rollback). They need a helper enhancement (the one-shot marker) + a VM-prove. Each CAT-C terminal + recovery path verified below against the CODE (not the fabricate-legacy contract — same lesson as the resume-death family).

## 1. :388 mid-migration-kill + :911 between-migrations-kill — one-shot KillHere → forward-recovery → COMPLETED
**Inject mechanics:** migrate.go:388 (during a migration's execution) / :911 (between migration N recorded and N+1) — `inject.KillHere(class)`. The kill is gated on ATOMICALLY consuming a marker: `os.Remove(STATBUS_INJECT_KILL_AND_REMOVE_FILE)` returns nil → fire (os.Exit 137); the file is removed BEFORE exit (inject.go:426-448, STATBUS-022) → fires EXACTLY ONCE; the marker survives the exec, so the recovery migrate re-enters the SAME site with the marker GONE → no re-kill.
**Self-heal SAFE (key — unlike the resume-death family):** the mid-migrate kill leaves migrations PENDING (the killed migration unrecorded/partial; :911 leaves N+1 pending) → `migrate.HasPending == true` → resumePostSwap's self-heal canary (:5053) does NOT fire → applyPostSwap → migrate.Up re-runs → forward-recovery. The PENDING migration is what defeats the self-heal here (the resume-death family left no-pending → self-heal).
**Helper enhancement (NEW):** `arc_install_dispatch_with_inject` (arc-helpers.sh:287) currently sets only STATBUS_INJECT_AT. Add a ONE-SHOT-MARKER mode: create a marker file on the VM + set `STATBUS_INJECT_KILL_AND_REMOVE_FILE=<path>` (alongside STATBUS_INJECT_AT). 1st dispatch → kill fires once (removes marker, exit 137) → 2nd recovery dispatch (marker GONE → KillHere's os.Remove fails → no re-kill) → migrate.Up completes.
**Contract:** 1st dispatch exit 137 (PostSwap, mid-migrate, HasPending) → recovery dispatch → forward-recovery → **completed + db.migration max BUMPED** to the target + data intact + flag absent + healthy. (db.migration-bumped is the load-bearing proof the forward-recovery applied for real.)
**VM-prove:** ONE representative (foreman's call — :388 or :911; :911 needs a ≥2-migration fixture so N-recorded/N+1-pending is real). VERIFY the REAL forward-recovery (the legacy contract was fabricate-based → the run is the oracle).

## 2. :202 mid-tx-kill — MidTxPauseSQL + harness tree-SIGKILL → clean re-apply → COMPLETED
**Inject mechanics:** migrate.go:436 splices `inject.MidTxPauseSQL(class)` (inject.go:506) into the migration's OUTER tx → the migrate psql PAUSES mid-tx (before COMMIT). The harness then tree-SIGKILLs the psql + pg_terminate_backend's the parked backend → the UNCOMMITTED tx ROLLS BACK → recovery → migrate re-runs → clean re-apply (nothing was committed) → completed.
**Helpers EXIST (just wire in):** `wait_for_midtx_stall_ready` (wedge-helpers.sh:418, detects the parked psql) + `kill_pid_in_vm` (:476, tree-SIGKILL). No new helper needed — wire them into an arc.
**Self-heal SAFE:** the rolled-back tx leaves the migration UNapplied → HasPending=true → no self-heal → forward-recovery → completed.
**Contract:** dispatch (STATBUS_INJECT_AT=killed-by-system-during-migration-tx-before-commit) → wait_for_midtx_stall_ready → kill_pid_in_vm (tree-SIGKILL) → recovery dispatch → completed + db.migration bumped + data intact. **VM-prove** (NEW — manual tree-SIGKILL mechanism).

## 3. :844/:845 migrate-killed-after-commit — StallHere + harness SIGKILL → forward-FAILS → ROLLED_BACK (rune shape)
**Inject mechanics:** migrate.go:844/:845 `inject.StallHere(...)` in the ~ms window AFTER a migration's outer tx COMMITS but BEFORE the db.migration ledger INSERT. The harness `wait_for_inject_stall_ready` → SIGKILL during the stall → the migration is COMMITTED-but-UNRECORDED. Recovery → resumePostSwap → self-heal check: HasPending=TRUE (ledger row missing → migrate thinks it's pending) → no self-heal → applyPostSwap → migrate.Up re-hits the committed-but-unrecorded migration → **re-apply CONFLICTS** (already applied) → migrate FAILS → postSwapFailure → rollback → **rolled_back** (the rune shape).
**DETERMINISM (load-bearing, like rollback-kill):** the rolled_back is deterministic ONLY if the re-apply RELIABLY conflicts. → the after-commit V fixture MUST be NON-IDEMPOTENT (e.g. `CREATE TABLE x` without IF NOT EXISTS → re-apply errors `already exists`). An idempotent V would forward-recover (→ completed), not rollback. So the fixture-design IS the determinism control.
**Contract:** dispatch → wait_for_inject_stall_ready → SIGKILL → recovery → forward-fails → rolled_back + data restored (the rune snapshot) + flag absent + healthy. Assert DETERMINISTICALLY (rolled_back, NOT both-outcomes). **VM-prove** (NEW + determinism-sensitive — the run confirms the non-idempotent re-apply reliably rolls back; watch fabricate-vs-real, the legacy needed a one-off run to confirm rolled_back).

## 4. worker-ddl-deadlock — NORMAL GREEN reshape (R1 quiesce ALREADY implemented; STATBUS-100 CLOSED — NOT a King-flag)
**CORRECTION (2026-06-19, code-verified by architect + foreman):** my original "KING-FLAG, R1 not implemented" was WRONG — read off the STALE legacy header ("LIKELY RED @ commit 1f077e545"), which PREDATES the fix. The R1 quiesce-services-before-DDL fix IS implemented on BOTH paths (compose.QuiesceClients, cli/internal/compose/compose.go:126; INSTALL cli/cmd/install.go:676 before Seed+Migrations; UPGRADE cli/internal/upgrade/service.go:4663 in applyPostSwap BEFORE the migrate DDL at :4751 — order reconnect→quiesce→migrate→restart; comment :4654 covers the resumePostSwap re-entry). STATBUS-100 CLOSED as already-implemented. So worker-ddl is a NORMAL GREEN-ASSERTING reshape, NOT a King-flag.
**Mechanism (scenario C13/R1):** class migration-deadlocks-with-running-worker-holding-table-lock. A worker holding AccessShareLock on statistical_history + a migration taking AccessExclusiveLock on the same target → Postgres lock manager PARKS the migration indefinitely → systemd TimeoutStartSec → wedge. Reproduction is REAL (no inject site, no fabricated deadlock): start_continuous_worker_workload (enqueue statistical_history_reduce every 2s → worker holds the lock) + B = A + a DDL migration on statistical_history.
**RESHAPE (in-charter, GREEN-asserting):** the fixture is REAL (no inject site, no fabricated deadlock) — start_continuous_worker_workload (worker holds AccessShareLock) + B = A + a DDL migration on statistical_history; the scheduled-row fabrication retires via register/schedule like the others. On current code the R1 quiesce (service.go:4663) stops the worker BEFORE the migrate DDL → no lock conflict → migrate succeeds → **completed** (the upgrade does NOT hang — doc/upgrade-timeline.md:266/:702).
**CONTRACT (GREEN):** install A → start the continuous worker workload (worker active, holding the lock) → register/schedule B (DDL migration on statistical_history) → the daemon upgrade R1-quiesces the worker → migrate applies → completed + db.migration bumped + data intact + healthy + bounded restarts. The scenario is POSITIVE REGRESSION-PROOF of the R1 fix (if R1 ever regressed → the upgrade would wedge → the scenario RED's via the in_progress/TimeoutStartSec budget). **(e)/anti-vacuous:** assert the worker workload was ACTUALLY running + holding the lock when the migrate ran (else the no-hang is vacuous) — e.g. confirm worker tasks in-flight + the lock present at schedule time.
**VM-prove:** YES (the worker↔migrate quiesce interaction is real-only; a GREEN-asserting run proves the R1 fix holds on the autonomous-upgrade path — which the existing Go/unit coverage of QuiesceClients does NOT exercise end-to-end). Build in 5d.

## 5. Shared-fixture refactor + matrix (the 5e enabler) — CAT-C fixture requirements
doc-016 §7's shared working/failing fixtures need CAT-C variants:
- **working-V (re-appliable):** for :388/:202 — a migration that the recovery re-runs cleanly (the migrate framework's tx + marker handle the partial/rolled-back application).
- **working-V multi-migration:** for :911 — ≥2 migrations so "N recorded, N+1 pending" is real.
- **non-idempotent-V:** for :844/:845 — re-apply must CONFLICT (deterministic rollback). DISTINCT from the re-appliable working-V.
- **failing-V (RAISE):** the existing failing arc + rollback-restore.
So the shared construct builds: working-V (re-appliable, multi-migration) + non-idempotent-V (after-commit) + failing-V. ~3 fixture lineages. The matrix run-arc (mirror STATBUS-025) fans out one VM per scenario with its inject class as a runtime param.

## 6. VM-prove strategy (B-REFINED, per NEW mechanism)
NEW mechanisms each get ONE VM-prove (representative): (a) one-shot KillHere forward-recovery (:388 OR :911); (b) :202 mid-tx tree-SIGKILL; (c) :844/:845 after-commit determinism. The same-mechanism site-variant (:388 vs :911, if one is proven) rides + review. worker-ddl = GREEN-asserting reshape (R1 quiesce ALREADY implemented; STATBUS-100 closed) → VM-prove in 5d as positive regression-proof of the existing fix on the autonomous-upgrade path. The 5e matrix full-suite runs EVERY reshaped scenario before fabricate is deleted (the per-scenario oracle). EACH CAT-C contract VERIFIED against the REAL run (the fabricate-legacy contracts are NOT the oracle — the resume-death-family lesson).

## 7. Phasing within 5d
5d-a: the one-shot-marker helper enhancement + :388/:911 (one VM-prove). 5d-b: :202 mid-tx (wire wait_for_midtx_stall_ready + kill_pid_in_vm; VM-prove). 5d-c: :844/:845 after-commit + the non-idempotent-V (VM-prove). 5d-d: the shared-fixture refactor + matrix mode. 5d-e: worker-ddl King-flag (backlog entry, run by King). Then 5e (matrix full-suite → delete fabricate).
