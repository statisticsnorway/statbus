# Recovery-injection scope (a) comprehensive — scenario inventory + execution plan

**Created 2026-05-22 from the recovery-injection-arc on branch `engineer/upgrade-recovery-validation` (currently at `38e44b111`).**

This is the comprehensive scope-(a) plan as agreed: every named failure class gets an empirical scenario. Living document — user has additional classes incoming.

## North Star reminder

`./sb install` is the single self-healing operator entrypoint. From any non-catastrophic state, re-running it converges the system to a coherent terminal state without operator judgment. **AND** we have empirically validated this property — for every named failure class, a harness scenario causes the failure deterministically and verifies that recovery converges. The empirical part is the load-bearing half.

## No-hotfix discipline (load-bearing, established 2026-05-22)

**The count that made this load-bearing — corrected 2026-05-22 with the actual denominator:**

| Stable release | RCs cut to ship it |
|---|---|
| v2026.03.0 | 52 |
| v2026.03.1 | 19 |
| v2026.04.0 | **69** |
| v2026.05.0 | 14 |
| v2026.05.1 | 1 |
| v2026.05.2 | 6 |
| v2026.05.3 | 1 |
| v2026.05.4 | 2 |
| v2026.05.5 | 1 (in flight) |
| **Total** | **166 RCs → 8 stable releases (5% success rate per cut)** |

Each failed RC = at least one bug found and fixed before the next cut. Across all releases: roughly 158 such fix cycles. The "Fix 1 → Fix 11" numbered hotfixes I'd cited earlier were a small named subset of this much larger reactive-fix population.

The compounding cost: each hotfix-without-tests introduces probability of another silent regression. Fix 8 → Fix 11 is the textbook case — Fix 8 was silently broken for 3 RCs before someone noticed. Scale that pattern across 158 fix cycles and the harness work becomes the obvious lever.

**Discipline:**
1. Every issue surfaced (tonight or in future incidents) is fixed IN this branch, paired with a scenario that validates the fix.
2. No fix ships before its scenario goes green on Hetzner.
3. Next release is gated on the full harness suite passing — no exceptions.
4. The "hotfix for urgent issue, test later" pathway is closed. If something feels too urgent to fully test, that's evidence the issue belongs in this branch, not a separate hotfix.

## Must-haves for the next release (the next-release gate)

These are the fixes that MUST land + validate empirically before any next release. Not "if time permits"; these are the gate.

| # | Fix | Class(es) | Status |
|---|---|---|---|
| 1 | R5 narrow: DB-content classifier in `checkSeedRestored` | C17 | ✅ **fix done** — commit `5dc66c237` (#159 closed). Scenario `394b187cd` (#138) ready to validate on Hetzner. |
| 2 | R1 narrow: service quiescence before DDL via `compose.QuiesceClients()/ResumeClients()` | C13 | ✅ **fix done** — commit `02a144052` (#158 closed). Scenario `6142b9cc6` (#139) ready to validate on Hetzner. |
| 3 | Race B root cause: `sdNotifyExtendTimeout` is a no-op in active phase — delete it, ticker uses `WATCHDOG=1` | C12 | ✅ **fix done** — commit `e6df084b7` (#161 closed). `sdNotifyExtendTimeout` + its 4 tests + 18-line doc block all deleted; the 2 call sites in applyPostSwap's migrate ticker now send `sdNotify("WATCHDOG=1")`. Subprocess-wrap audit confirmed no other site needed the change. Scenario #140 pending. |
| 3a | `TimeoutStartSec=120` declared explicitly in service file | n/a | ✅ **done** — commit `f43b2bfd1` (#160 closed). One limit to reason about, eliminates implicit 90s default footgun. |
| 4 | pg_restore single-tx audit + stderr-ERROR scan | n/a (code audit) | ✅ **done** — commits `9c48a8571` (single-tx → loud failure) + `1f077e545` (stderr-ERROR scan defense-in-depth) |

**More incoming.** User has additional observations from Albania to surface. The four-item list is not exhaustive — treat as the starting set, add Albania findings as they're characterized.

## Branch state at time of writing

- Branch: `engineer/upgrade-recovery-validation` at `2798a609e`
- Origin: matched (force-pushed)
- 52 commits ahead of `origin/master` (master moved forward 5 commits past the prior merge-base; harness work past that adds ~8 more)
- Two SSH-layer harness fixes landed for the "scp lost connection at ~30% of 22MB upload" bug surfaced on scenarios 16 (×2) + 26 (×1):
  - `5f82ab868` (`harness-controlmaster-fix`) — `SSH_OPTS` now includes `-o ControlMaster=no -o ControlPath=none` to prevent developer's global `~/.ssh/config` from multiplexing harness scp over a mux socket. Principled contamination prevention; kept even though not the root cause of THIS particular failure.
  - `2798a609e` (`harness-scp-legacy-protocol`) — all 7 scp calls now use `-O` to force legacy SCP protocol instead of SFTP. **True root cause**: macOS OpenSSH 10.0+ defaults to SFTP-mode scp which has a flow-control deadlock; `ServerAliveInterval=30 × ServerAliveCountMax=10 = 300s` timeout kills the stalled session. Empirically verified: rsync and `ssh 'cat>file'` also fail; only `scp -O` completes a 14.6MB transfer in one pass.
- 18 classes registered in `cli/internal/inject/inject.go` (KindKill / KindError / KindStall / KindExternal); Bug-1 class `archive-backup-stall-active-phase-watchdog` joined the registry at `69a67a5bc`.
- 18 scenarios written: `02`, `08`, `10`, `11`, `12`, `13`, `15`, `16`, `17`, `18`, `19`, `20`, `21`, `22`, `23`, `24`, `25`, `26` — all awaiting Hetzner validation. EVERY named class in the inject registry has a paired scenario; scenario 19 is full-fire; scenario 02 uses the fabrication helper; scenario 26 is the Bug 1 archiveBackup-watchdog reproducer.
- CI workflow `.github/workflows/install-recovery-harness.yaml` lands at `6b31741da`. `./sb release stable` preflight grows a 4th gate (`SKIP_INSTALL_RECOVERY=1` bypass). Activates the moment branch merges to master.
- Race D fix (WATCHDOG=1 ticker around `d.reconnect` in applyPostSwap) lands at `6db507fa0`. Closes the watchdog gap during DB reconnect after container restart.
- Bug 1 fix (WATCHDOG=1 ticker covers the WHOLE remainder of applyPostSwap, incl. archiveBackup's multi-GB tar) lands at `b7ee2a0ca`. Subsumes the older d416a50a0 migrate-only ticker; closes the rune.statbus.org 35-GB watchdog kill.
- Bug 2 fix (proxy added to step11RestartServices, aligning the canary's `versionTrackedServices` with what the upgrade pipeline actually restarts) lands at `81018a495`. Static invariant `TestVersionTrackedAlignedWithUpgradePipeline` (added at `ee8bba850`) guards against future drift.
- Harness helper `fabricate_scheduled_upgrade_row(vm, head_sha)` lands at `6db507fa0`. Inserts state='scheduled' rows directly when HEAD is untagged and discover wouldn't surface it. Used by scenarios 19 + 02 + 26.
- 4 backup tags maintained (rollback points if needed)
- C18 stricken — initial framing of `./sb stop` during install as a "collision" was wrong; it's emergency recovery for the R1 deadlock. Once R1 is fixed, the race becomes hypothetical.
- 2026-05-26 (parallel architectural deliverable, not in scope-a): `doc/install-image-distribution-design.md` drafted on branch `engineer/image-distribution-design` (commit `511d179f4`). ~1500-word design for consolidating the `sb` binary onto container-image distribution alongside the existing four service images, with a non-destructive 7-step migration sequence. Standalone of the harness arc; addresses the "166 RCs to 8 releases" inefficiency from a different angle (test-time artifact convergence). Awaiting user review.

## Inventory (17 classes today)

Numbered by registration order. Each class has slug, kind, real-world cause, layer-territory, status.

### Registered (17)

All 17 classes are registered in `cli/internal/inject/inject.go` as of commit `99ae765b2` (#137 closed). C13-C17 added a new `KindExternal` value to the taxonomy for classes with no in-code injection site (orchestration fully external).

| # | Class slug | Kind | Real-world cause | Layer | Scenario |
|---|---|---|---|---|---|
| C1 | `migrate-subprocess-killed-after-commit-before-recorded` | Stall | OOM/psql crash mid-canonical-window; parent in-process recovery | 0 | 08 Stage 1 ✓ |
| C2 | `upgrade-service-parent-killed-after-commit-before-recorded` | Stall | systemd/OOM kills parent at canonical moment; next-install recovery | 2 | 08 Stage 2 ✓ |
| C3 | `killed-by-system-during-preswap-backup` | Kill | systemd/OOM during DB backup phase | 2 | scenario 21 + inject site (`8c5ea71b9`) — Hetzner pending |
| C4 | `killed-by-system-during-preswap-checkout` | Kill | systemd/OOM during git checkout | 2 | scenario 22 + inject site (`8c5ea71b9`) — Hetzner pending |
| C5 | `killed-by-system-during-binary-swap` | Kill | systemd/OOM during binary-replace step | 2 | scenario 16 + inject site (`d0f7974e2`) — Hetzner pending |
| C6 | `killed-by-system-during-individual-migration-execution` | Kill | systemd/OOM during SQL execution of one migration | 2 | scenario 17 + inject site (`1ee2d4e11`) — Hetzner pending |
| C7 | `killed-by-system-between-migrations` | Kill | systemd/OOM between migration N and N+1 | 2 | scenario 23 + inject site (`089a90951`) — Hetzner pending |
| C8 | `killed-by-system-during-container-restart` | Kill | systemd/OOM during docker compose up after postswap | 2 | scenario 15 + inject site (`d0f7974e2`) — Hetzner pending |
| C9 | `killed-by-system-during-builtin-rollback` | Kill | Process killed mid-rollback after primary failure | 2 | scenario 24 (diagnostic) + inject site (`089a90951`) — Hetzner pending; firing non-deterministic |
| C10 | `concurrent-install-attempted-during-migrate-up` | Stall | Operator runs second install while first is in migrate phase | n/a (probe 2) | scenario 11 (`df2c96c0a`) — Hetzner pending |
| C11 | `service-startup-slower-than-systemd-unit-timeout` | Stall | Service startup exceeds `TimeoutStartSec`; SIGTERM | 1 | scenario 18 + inject site (`1ee2d4e11`) — Hetzner pending |
| C12 | `migration-slower-than-systemd-unit-timeout` | Stall | Migration SQL exceeds `TimeoutStartSec`; SIGTERM; restart loop | 1 | scenario 12 + inject site (`fa1c60724`) — Hetzner pending |
| C13 | `migration-deadlocks-with-running-worker-holding-table-lock` | Stall | Worker holds AccessShareLock; migration needs AccessExclusiveLock; deadlock (R1) | architectural | scenario 13 (`6142b9cc6`) — Hetzner pending |
| C14 | `install-flag-released-without-clean-handoff-detected-as-stale` | External | Install exits without releasing flag; upgrade-service interprets as crash (R3) | architectural | scenario 20 (`8c5ea71b9`, diagnostic — no inject site, KindExternal) — Hetzner pending |
| C15 | `service-watchdog-timeout-during-db-reconnect-after-container-restart` | Stall | WatchdogSec=2min not pinged during reconnect; SIGABRT (Race D) | 1 | scenario 19 (full-fire) + inject site + Race D fix (`6db507fa0`) — Hetzner pending |
| C16 | `advisory-lock-attempted-before-db-ready-after-container-restart` | External | Service tries advisory lock before DB ready; exits, restarts (Race E) | architectural | scenario 25 (`089a90951`, external orchestration — no inject site, KindExternal) — Hetzner pending |
| C17 | `seed-restore-runs-on-populated-database-destroying-data` | Stall | State machine triggers seed restore against populated DB — DATA LOSS (R5) | architectural | scenario 10 (`394b187cd`) — Hetzner pending (harness Bug A/B fixed in `a0ca54eb4` per #162; re-run dispatched) |
| ~~C18~~ | ~~`docker-compose-restart-collides-with-concurrent-stop`~~ | — | **STRICKEN 2026-05-22.** Initial framing was wrong. `./sb stop` during install is *emergency recovery* (operator's lever to break a deadlock), not a collision. Adding a lock that refused stop would close the emergency exit. **Primary fix is C13 (R1: service quiescence before DDL).** Once R1 is fixed, the deadlock doesn't happen, operator doesn't need emergency stop, this race becomes hypothetical. A secondary regression net for cloud.sh's post-install handling of ongoing teardown may be worth a future scenario, but it's not load-bearing for the next release. | — | n/a (stricken) |

## Per-scenario template

Each scenario follows this shape:

```bash
#!/bin/bash
# Scenario NN: <slug>
# Validates class C<N>: <class-name>
# Real-world cause: <one sentence>
# Recovery expectation: <one sentence>

set -euo pipefail
VM_NAME="${1:-statbus-recovery-NN}"
INSTALL_VERSION="${INSTALL_VERSION:-v2026.05.4}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"
source "$LIB_DIR/vm-bootstrap.sh"
source "$LIB_DIR/wedge-helpers.sh"
source "$LIB_DIR/assertions.sh"
source "$LIB_DIR/data-helpers.sh"

trap 'rc=$?; cleanup_vm "$VM_NAME"; exit $rc' EXIT

# Phase 1: Bootstrap
bootstrap_install_test_vm "$VM_NAME" "$INSTALL_VERSION"

# Phase 2: Initial install at known version
install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"
assert_health_passes "$VM_NAME"

# Phase 3: Populate (where applicable; for scenarios testing populated-DB)
populate_with_demo_data "$VM_NAME"
DATA_SNAPSHOT=$(snapshot_demo_data_counts "$VM_NAME")

# Phase 4: Start workload (where applicable; for scenarios needing live worker)
start_continuous_worker_workload "$VM_NAME"

# Phase 5: Set up injection (env vars, release files as needed)
# Phase 6: Trigger upgrade with injection
# Phase 7: Verify wedge (assert specific RED state)
# Phase 8: Recovery (`./sb install` with no injection)
# Phase 9: Verify convergence
assert_upgrade_row_state "$VM_NAME" "rolled_back"   # or "completed"
assert_systemd_restart_counter_bounded "$VM_NAME" "statbus-upgrade@<slot>" 2
assert_demo_data_present "$VM_NAME"                  # R5 catastrophic-loss detector
assert_demo_data_counts_match_snapshot "$VM_NAME" "$DATA_SNAPSHOT"  # data integrity

# Phase 10: Cleanup
stop_continuous_worker_workload "$VM_NAME"
```

## Per-class detailed specs

### C3 — `killed-by-system-during-preswap-backup`

- **Injection site**: in `executeUpgrade`'s backup phase, between starting the backup and recording completion. New `inject.KillHere` call.
- **Setup**: populated DB, workload optional
- **Trigger**: schedule upgrade with `STATBUS_INJECT_AT=killed-by-system-during-preswap-backup`; process dies during backup
- **Wedge**: flag file present, no PostSwap stamp, partial backup dir on disk
- **Recovery**: next install detects crashed-upgrade, recoverFromFlag's PreSwap branch handles (binary still old), discards partial backup, clears flag
- **Assertions**: state=`failed` or new install discards backup and is healthy at old version; flag absent; data intact

### C4 — `killed-by-system-during-preswap-checkout`

- **Injection site**: in `executeUpgrade`'s git-checkout phase, mid-checkout. New `inject.KillHere`.
- **Setup**: populated DB
- **Trigger**: `STATBUS_INJECT_AT=killed-by-system-during-preswap-checkout`
- **Wedge**: flag file, no PostSwap, working tree possibly dirty
- **Recovery**: next install detects crashed-upgrade, restoreGitState resets working tree, discards backup, clears flag
- **Assertions**: post-recovery git status clean; binary version unchanged; data intact

### C5 — `killed-by-system-during-binary-swap`

- **Injection site**: in the binary-swap step, mid-rename or just after. New `inject.KillHere`.
- **Setup**: populated DB
- **Trigger**: `STATBUS_INJECT_AT=killed-by-system-during-binary-swap`
- **Wedge**: flag file, binary may be partially-new or fully-new but no migrations applied
- **Recovery**: next install detects crashed-upgrade, recoverFromFlag determines binary state, rolls forward via migrate.Up or rolls back via restoreBinary
- **Assertions**: terminal state coherent (either rolled_back at old version or completed at new); data intact

### C6 — `killed-by-system-during-individual-migration-execution`

- **Injection site**: inside `runPsqlFile` mid-execution OR right before `runPsqlFile` in the migration loop. New `inject.KillHere` OR stall + external kill.
- **Setup**: populated DB
- **Trigger**: `STATBUS_INJECT_AT=killed-by-system-during-individual-migration-execution`
- **Wedge**: flag file, binary new, migration mid-execution (transaction rolled back), db.migration not updated
- **Recovery**: next install detects crashed-upgrade, attempts forward, succeeds (migration's transaction was atomic, so its effects are gone — clean retry)
- **Assertions**: state=`completed` after recovery, migration applied cleanly, data intact

### C7 — `killed-by-system-between-migrations`

- **Injection site**: in the migration loop, between migration N's success and migration N+1's start. New `inject.KillHere`.
- **Setup**: populated DB with at least 2 pending migrations to ensure the "between" point exists
- **Trigger**: `STATBUS_INJECT_AT=killed-by-system-between-migrations`
- **Wedge**: flag file, binary new, N applied (in db.migration) and recorded, N+1 not started
- **Recovery**: next install detects crashed-upgrade, forward-recovery applies N+1 cleanly
- **Assertions**: state=`completed`, db.migration includes both N and N+1, data intact

### C8 — `killed-by-system-during-container-restart`

- **Injection site**: in `applyPostSwap`'s container-restart step, mid `docker compose up` or during health-check loop. New `inject.KillHere`.
- **Setup**: populated DB
- **Trigger**: `STATBUS_INJECT_AT=killed-by-system-during-container-restart`
- **Wedge**: flag file, binary new, migrations applied, containers in indeterminate state (some up, some not)
- **Recovery**: next install detects crashed-upgrade, completes container restart, health-check
- **Assertions**: state=`completed`, all services healthy, data intact

### C9 — `killed-by-system-during-builtin-rollback`

- **Injection site**: inside `d.rollback()` pipeline (e.g., between restoreDatabase and restoreBinary). New `inject.KillHere`.
- **Setup**: populated DB. Requires first failing the upgrade (e.g., via a chained injection that triggers rollback, then killing during rollback). Two-stage scenario.
- **Trigger**: deliberately fail the upgrade to enter rollback, then inject kill mid-rollback
- **Wedge**: flag file, partial rollback state (DB partially restored, binary not yet rolled back)
- **Recovery**: next install detects crashed-upgrade, completes the rollback from wherever it stopped
- **Assertions**: state=`rolled_back`, binary back at old version, data intact at pre-upgrade snapshot

### C10 — `concurrent-install-attempted-during-migrate-up`

- **Injection site**: already exists — `inject.StallHere` in `migrate.runUp` (registered, called)
- **Setup**: populated DB, no workload (we want clean live-upgrade state for probe 2 to detect)
- **Trigger**: start first install with stall injection; while stalled, run second install
- **Wedge**: first install holding flag + PID alive; second install detects live-upgrade via probe 2
- **Recovery**: second install refuses with `live-upgrade` diagnostic; first install released and completes
- **Assertions**: second install exits with refuse code + matching PID message; first install completes; only one terminal upgrade row

### C11 — `service-startup-slower-than-systemd-unit-timeout`

- **Injection site**: in upgrade-service entry point (before main work begins), `inject.StallHere`. New site.
- **Setup**: minimal — fresh install OK
- **Trigger**: configure short TimeoutStartSec, start upgrade-service unit with STATBUS_INJECT_AT set; systemd SIGTERMs after timeout
- **Wedge**: depends on Layer 1's handling of SIGTERM. Could be restart loop OR clean abort.
- **Recovery**: assert restart counter bounded (no infinite loop); upgrade row in terminal state (`failed` or unchanged)
- **Assertions**: `assert_systemd_restart_counter_bounded` ≤ 2; upgrade row not stuck in `running`

### C12 — `migration-slower-than-systemd-unit-timeout`

- **Injection site**: inside `runPsqlFile` or right before it, `inject.StallHere`. New site (or reuse mid-migration site).
- **Setup**: populated DB, ideally with workload contention to make migration "real" slow
- **Trigger**: configure short TimeoutStartSec; trigger upgrade with stall injection in migration
- **Wedge**: SIGTERM fires mid-migration; service may restart
- **Recovery**: same as C11 — assert restart bounded
- **Assertions**: restart counter ≤ 2; migration not re-attempted indefinitely; data intact

### C13 — `migration-deadlocks-with-running-worker-holding-table-lock` (R1)

- **Injection site**: register class; harness uses `start_continuous_worker_workload` for the worker contention. No NEW injection site needed if the workload generator naturally produces AccessShareLock contention against tables migration would touch.
- **Setup**: populated DB, **continuous worker workload running**
- **Trigger**: trigger upgrade; migration's `CREATE/DROP INDEX` blocks on worker's AccessShareLock
- **Wedge**: migration hangs indefinitely waiting for lock
- **Recovery**: depends on install state machine. Currently: nothing — tcc had to be manually stopped. With Layer 1: SIGTERM should eventually kill the migration, recovery loop applies.
- **Assertions**: migration does NOT hang indefinitely (timeout-bounded); upgrade reaches a terminal state; data intact
- **NOTE**: This class might surface a real architectural bug. Per the forensics, R1 needs a quiesce-services-before-DDL fix in the install state machine. The scenario validates whatever the current behavior is.

### C14 — `install-flag-released-without-clean-handoff-detected-as-stale` (R3)

- **Injection site**: no in-code injection. External orchestration: run install to clean exit, then observe upgrade-service's behavior on the orphan flag.
- **Setup**: fresh install (no upgrade needed)
- **Trigger**: run `./sb install` to clean exit; check `tmp/upgrade-in-progress.json` state after
- **Wedge**: flag file present (install didn't release), holder PID dead (install exited)
- **Observed behavior**: upgrade-service on next tick interprets as crashed-install, clears flag
- **Assertions**: this is more of a behavioral observation test — assert the journal shows the "stale flag" message, OR assert the flag is correctly handled
- **NOTE**: Per forensics, this race is a real bug. Test exists to flag the behavior; fix is install must release flag on clean exit.

### C15 — `service-watchdog-timeout-during-db-reconnect-after-container-restart` (Race D)

- **Injection site**: inside the reconnect loop in upgrade-service, `inject.StallHere`. New site.
- **Setup**: fresh install + upgrade scheduled
- **Trigger**: trigger upgrade; mid-postswap, restart DB container externally; stall the reconnect for > 2min
- **Wedge**: WatchdogSec fires, service SIGABRT'd
- **Recovery**: systemd restarts service; reconnect succeeds quickly
- **Assertions**: upgrade eventually completes; restart counter bounded (1 restart, not loops)
- **Fix-suggesting**: per forensics, should ping WATCHDOG=1 from inside reconnect loop

### C16 — `advisory-lock-attempted-before-db-ready-after-container-restart` (Race E)

- **Injection site**: no in-code injection. External orchestration: restart DB container, immediately start upgrade-service.
- **Setup**: fresh install + upgrade scheduled
- **Trigger**: restart DB container; immediately start statbus-upgrade@slot.service
- **Wedge**: service exits 42 (advisory lock attempt fails on cold DB)
- **Recovery**: systemd restarts service after backoff; second attempt succeeds
- **Assertions**: upgrade completes; restart counter ≤ 2

### C17 — `seed-restore-runs-on-populated-database-destroying-data` (R5) — **DATA LOSS CRITICAL**

- **Injection site**: no in-code injection. External orchestration: populate DB, then trigger install with state forcing seed step.
- **Setup**: populated DB
- **Trigger**: somehow force install to run `[10/15] Seed RUNNING` step against a populated DB. Per forensics, this can happen when state probes as "nothing-scheduled" + migration tail mismatch.
- **Wedge**: install starts destructive `pg_restore` of seed; could complete and destroy data, or deadlock and be saved by R1 (tcc's luck)
- **Recovery**: install machine should REFUSE seed on populated DB and route to `migrate-forward` instead
- **Assertions**: `assert_demo_data_present` (PASS = data survived); install ends in terminal state (either succeeded by going forward-only, OR refused with diagnostic)
- **NOTE**: Per forensics, R5 requires an install state-machine fix (classify DB content before deciding action). The scenario surfaces whether the fix is in place.

## Implementation order (priority)

By urgency / damage-potential / coverage value:

1. **C17 R5 seed-on-populated** — data-loss-grade, highest urgency
2. **C13 R1 worker-deadlock** — most-damaging per forensics
3. **C12 migration-timeout** — tonight's active dev pathology
4. **C10 concurrent-install** — probe 2 detection validation
5. **C8 container-restart-kill** — state-bearing PostSwap phase
6. **C5 binary-swap-kill** — state-bearing transition
7. **C6 mid-migration-kill** — common Layer 2 case variant
8. **C11 service-startup-timeout** — companion to C12
9. **C15 watchdog-reconnect (Race D)** — self-heals but worth catching
10. **C14 flag-stale-handoff (R3)** — behavior surfacing
11. **C3 preswap-backup-kill** — early-phase variant
12. **C4 preswap-checkout-kill** — early-phase variant
13. **C7 between-migrations-kill** — rare but distinct phase
14. **C9 rollback-kill** — recursive case, rare
15. **C16 advisory-too-early (Race E)** — self-heals
16. **02 happy-upgrade** — baseline scenario (no failure injection)

## CI gate plan (final step)

After all scenarios pass empirically on the branch:

1. New file: `.github/workflows/install-recovery-harness.yaml` — workflow that:
   - Triggers on prerelease tag creation
   - Provisions a runner (or uses self-hosted with hcloud access)
   - Runs the full scenario suite
   - Posts results to PR / commit
2. Add to release-stable's preflight via `CheckWorkflowAtCommit` helper (existing from #120):
   - Refuses to promote prerelease → stable unless this workflow is green at the prerelease's commit
3. This lives as a commit on the branch — activates the moment the branch merges

## Implementation cadence

Each scenario is one commit (or two if it adds a new injection site). Lands on the branch. Force-push as you go. Branch stays parkable at any cumulative pass.

Engineer should pause between scenarios for foreman review of the design decisions in each:
- Where to place the injection site (if new)
- What the exact wedge state looks like
- What assertions are load-bearing

Don't burn Hetzner cycles on the wrong test design — review the script's design before the first run.

## Open slots for additional classes

User has additional failure classes incoming. They slot in here as C18, C19, … with the same spec format. Each becomes a new task in the scenario queue.

```
C18 — <slug>
- Real-world cause:
- Setup:
- Trigger:
- Wedge:
- Recovery:
- Assertions:
- Priority:
```

## Task tracking

Tasks created alongside this document:
- ~~`register-forensics-classes` (#137)~~: register C13-C17 in `cli/internal/inject/inject.go` + doc inventory — **done**, commit `99ae765b2`
- ~~One task per scenario implementation (C3-C17 + 02 happy-upgrade = 16 tasks, #138-#153)~~ — **all 16 scenarios written and on branch.** Hetzner validation status tracked separately under #155. As of 2026-05-23 23:30: #138 (scenario 10 / C17-R5) GREEN ✓, #139 (scenario 13 / C13-R1) GREEN ✓, #140 (scenario 12 / C12) RED under #164 diagnosis, rest pending in current cascade.
- ~~`scope-a-ci-workflow` (#154)~~: workflow YAML on branch — **done**, commit `6b31741da` (`.github/workflows/install-recovery-harness.yaml` + `release.WorkflowInstallRecoveryHarness` constant + 4th `checkStableWorkflowGate` in `cli/cmd/release.go` with `SKIP_INSTALL_RECOVERY=1` bypass)
- `scope-a-full-validation` (#155): final full-suite Hetzner run
- ~~`c15-watchdog-fire-followup` (#163)~~: full systemd-unit watchdog firing test for Race D — **done**, commit `6db507fa0` (WATCHDOG=1 ticker around `d.reconnect` + `fabricate_scheduled_upgrade_row` harness helper + scenario 19 promoted from diagnostic-only to full-fire + scenario 02 robustness via same helper). Crossed with foreman's deferral message; engineer's three-layer batch already in flight when the deferral arrived.
- ~~`scenario-12-heredoc-fix` / `scenario-12-stall-rootcause` (#164)~~: scenario 12 RED on Hetzner debug — **done**. Three layers: (1) heredoc-over-ssh → fixture+scp at `816ff7194`. (2) Then RED again, root-caused: scenario 12's Phase 3 bypasses `install_statbus_in_vm`, so #162's `/tmp/sb` fix never applied. Fix at `04db5c641` adds the missing scp before tmux-start + improves stall-wait failure surfacing. (3) Preventive follow-up: same Phase-3-custom-script pattern was widespread, mechanic patched 12 scenarios in `5a98a956c` via `upload_sb_to_vm()` helper extraction. Mechanic also confirmed: install state-machine reaches `migrate.runPsqlFile` on second invocation (Images skip → Services skip → Seed skip → Migrations run), validating the install-ladder design and ruling out hypothesis-(b) "install exits early" categorically.
- ~~`scenario-script-perms` (#165)~~: install scripts uploaded by scp lack read+execute permission — **done**, commit `3240d4d4e`. Surfaced on scenario 15's first run at `5a98a956c`. Root cause: `mktemp` defaults host-side script file to 0600; scp preserves source mode; remote file lands root:root 0600; `sudo -u statbus bash /tmp/...` fails on read() (not execve()). Fix: `upload_install_script_to_vm()` helper that scps + chmods 0755 + removes local temp. Applied to 9 scenarios (11, 12, 15, 16, 17, 21, 22, 23, 24 with two scripts). Scenarios 02, 08, 19 verified clean (no `cp /tmp/install-*.sh` pattern).
- ~~`scenario-sb-swap-atomic` (#166)~~: `cp /tmp/sb ./sb` hits ETXTBSY on running binary — **done**, commit `be8bfdb06`. Surfaced on scenario 15's run 4 at `3240d4d4e`. Root cause: `statbus-upgrade@*.service` systemd unit holds `./sb` open as its executable; Linux refuses to overwrite a running executable's inode. Fix (option c): `upload_sb_to_vm()` extended to do production-shape mv-then-cp atomic swap (`mv ./sb ./sb.old; cp /tmp/sb ./sb; chmod+x; chown statbus; rm ./sb.old`). Mirrors `replaceBinaryOnDisk` in `cli/internal/upgrade/service.go`. All `cp /tmp/sb ./sb` execution lines removed from install scripts across 12 affected scenarios. Net -36 lines.
- ~~`upload-sb-staleness` (#167)~~: helper doesn't rebuild when host source advances — **done**, commit `c4c1b8aeb`. Surfaced on scenario 15's run 5 at `be8bfdb06`. Root cause: host's `sb-linux-amd64` was built from master commit `9901bbf7` before the branch diverged; `upload_sb_to_vm()` builds "if absent" so it reused the stale binary for 60+ commits. VM's `stalenessGuard` PersistentPreRun in `cli/cmd/root.go:85` compares binary's embedded `commitSHA` (baked via ldflags) against current cli/ tree, detects mismatch on `install` (Annotations: {selfheal: true}), triggers `freshness.RebuildAndReexec()`, fails on Hetzner cx23 (no Go toolchain) with exit 127. Fix (option a — always rebuild): `upload_sb_to_vm()` unconditional `go build -o sb-linux-amd64` when `STATBUS_SB_BINARY` override absent. ~10-15s overhead per scenario, irrelevant against ~10-15min Hetzner wall-clock. `STATBUS_SB_BINARY` bypass preserved for CI pre-built-artifact workflows. **Closes the five-commit harness-debug arc:** heredoc → /tmp/sb missing → script-perms → ETXTBSY → staleness. Pattern: every harness-vs-production divergence in setup-phase I/O caused a class of REDs; fixes consistently match production behavior.
- ~~`scenario-15-dbus` (#168)~~: `systemctl --user daemon-reload` fails "No medium found" — **done**, commits `87809ed4f` (initial broken text-match) + `c02aa0976` (replacement precondition-probe). Surfaced on scenario 15's run 6 at `c4c1b8aeb`. Root cause: fresh install ordering — `runInstallService` (install.go:1631) calls daemon-reload BEFORE `loginctl enable-linger` starts the user session bus. **Two-iteration fix:** (1) mechanic's first attempt `87809ed4f` used `strings.Contains(err.Error(), "No medium found")` — engineer review found this unreachable (`runCmd` streams stderr to terminal, doesn't capture into Go error value; `err.Error()` only contains "exit status 1"). (2) mechanic's replacement `c02aa0976` switches to pre-hoc precondition probe: `os.Stat($XDG_RUNTIME_DIR/bus)` BEFORE invoking daemon-reload; if socket absent → skip with diagnostic; if present → run daemon-reload, any failure is hard error. Robust against systemctl version text variations, no stderr capture needed. Engineer's separate architectural finding (`runInstallRootService` is dead code, recommend option d for invocation-mode dispatch) tracked as #169 for user morning review.
- `install-mode-dispatch` (#169): route `runInstallService` by Geteuid+XDG (engineer's option d) — **pending user review**. Resurrect dead `runInstallRootService` code and wire it for root invocation; preserve user-level path for service-user-with-session; fail-fast for service-user-no-session. User input needed on: resurrect vs rewrite the dead code, harness invocation shape, niue migration cost. (Engineer's full design report is in the personal plans archive.)

Total: 1 + 16 + 4 = 21 tasks. See task list for slugs.

## Branch state checkpoints

- 2026-05-22 (initial): `38e44b111` — 11 commits ahead of master after rebase + 4 harness primitives.
- 2026-05-22 (post #137): `99ae765b2` — 12 commits ahead, all 17 classes registered with `KindExternal` for C14/C16.
- 2026-05-22 (post #138 code-only): `394b187cd` — 13 commits ahead, C17 scenario file landed at `test/install-recovery/scenarios/10-seed-on-populated.sh`. Not yet Hetzner-validated (likely RED on current code; gated on architectural fix).
- 2026-05-22 (post #156): `9c48a8571` — 14 commits ahead. Side-audit out of scope-(a) but on-branch per the no-hotfix discipline: `cli/cmd/seed.go` pg_restore wrapper silently turned `--single-transaction` ROLLBACK (exit 1) into "passing invocation" via legacy exit-1-tolerance. Removed; any non-zero exit now propagates. Pairs naturally with C17 — the wrapper bug was the silent-success path the R5 scenario exists to detect. Rest of the pg_restore + destructive-op surface audited clean.
- 2026-05-23 (post 4-commit must-haves batch): `e6df084b7` — 39 commits ahead. Four must-have fixes for the next release all landed: R1 quiesce (`02a144052`, #158), R5 classifier (`5dc66c237`, #159), TimeoutStartSec=120 (`f43b2bfd1`, #160), Race B WATCHDOG=1 + `sdNotifyExtendTimeout` deletion (`e6df084b7`, #161). All four code-only; Hetzner validation of scenarios #138 + #139 (and #140 once written) is the next phase.
- 2026-05-23 (post #140 C12 scenario): `fa1c60724` — 40 commits ahead. Scenario `12-migration-timeout.sh` + paired `inject.StallHere` site in `runPsqlFile`. Validates the Race B fix landed in `e6df084b7`. Expected GREEN on the current branch.
- 2026-05-23 (post #141/#142/#143 batch): `d0f7974e2` — 46 commits ahead. Three scenarios + two new injection sites: `11-concurrent-install.sh` (C10, no new site — reuses existing C10 stall in `migrate.runUp`), `15-container-restart-kill.sh` (C8, new `inject.KillHere` in `applyPostSwap` between step 11 and step 12), `16-binary-swap-kill.sh` (C5, new `inject.KillHere` in `executeUpgrade` between `replaceBinaryOnDisk` and `updateFlagPostSwap`). All three expected GREEN on the current branch — they validate paths that already exist on master + this branch.
- 2026-05-23 (post #162 harness bug fixes): `a0ca54eb4` — 47 commits ahead. Two harness bugs surfaced by tester's first scenario-10 run, both fixed in one commit since they block the same operator-shape baseline (install-at-release → populate → re-install-at-HEAD): **Bug A** — `/tmp/sb` missing on the second install in `install_statbus_in_vm`'s no-version branch (only the local-HEAD bootstrap path uploaded it; the version-arg path downloaded sb from GitHub releases, leaving `/tmp/sb` absent for the subsequent `cp /tmp/sb ./sb`). Fix: scp host's `sb-linux-amd64` to `/tmp/sb` at top of no-version branch, idempotent, with `STATBUS_SB_BINARY` override and `./dev.sh build-sb` fallback. **Bug B** — `populate_with_demo_data` returned before worker derivation tasks drained (tester evidence: `legal_unit` + `establishment` stable, `statistical_unit` +55 and `statistical_history` +336 between snapshot and post-install check). Fix: new `wait_for_worker_quiesce(vm_name, max_wait_s)` primitive polls `worker.tasks WHERE state NOT IN ('completed','failed')` until 2 consecutive zero polls; chained into `populate_with_demo_data` after the import_job-terminal poll. Scenarios 10/12/13 should now reach their recovery-path assertions on the next Hetzner run. Build green; `bash -n` clean on both modified files; no Go code touched.
- 2026-05-23 (post #144/#145/#146 batch): `1ee2d4e11` — 49 commits ahead. Three scenarios + three new injection sites: `17-mid-migration-kill.sh` (C6 — new `inject.KillHere` at top of `migrate.runPsqlFile`, BEFORE the psql subprocess runs; recovery via clean forward-retry since migration's outer TX never opened), `18-startup-timeout.sh` (C11 — new `inject.StallHere` in `Service.Run` AFTER `checkMissedUpgrades` and BEFORE `READY=1`; tests static TimeoutStartSec=120s fires + bounded restart), `19-watchdog-reconnect.sh` (C15 / Race D — new `inject.StallHere` in `applyPostSwap` AFTER `waitForDBHealth` and BEFORE `d.reconnect(ctx)`; site-reachability diagnostic, NOT a runtime watchdog test). Design choice (a) for C11: keep TimeoutStartSec static, no activating-phase extender (the deleted `sdNotifyExtendTimeout` helper is NOT re-introduced). Scope note for C19: the watchdog itself is not testable without supervised-unit dispatch (manual `public.upgrade` row insert is out of scope); the scenario surfaces the missing-coverage gap empirically, fix shape (`WATCHDOG=1` ticker around reconnect mirroring `e6df084b7`) lands as a follow-up commit. Build + tests green; `bash -n` clean on all three scenarios. Branch state line as pushed: `1ee2d4e11` (origin matched).
- 2026-05-23 (post #147/#148/#149 batch): `8c5ea71b9` — 50 commits ahead. Three scenarios + two new injection sites: `20-flag-stale-handoff.sh` (C14 / R3 — external diagnostic, NO inject site since C14 is KindExternal; install → snapshot flag → wait one tick → re-check; surfaces the R3 leak as RED today, convergence via stale-flag clear path either way), `21-preswap-backup-kill.sh` (C3 — new `inject.KillHere` in `cli/internal/upgrade/exec.go`'s `backupDatabase` AFTER rsync + BEFORE the atomic rename; abort terminal state assertion explicitly rejects `completed`), `22-preswap-checkout-kill.sh` (C4 — new `inject.KillHere` in `executeUpgrade` AFTER the `git checkout commitSHA` subprocess + BEFORE the binary swap; load-bearing assertion that the working tree is restored to the pre-install OLD commit via `restoreGitState`). All three pre-binary-swap; principled terminal state is `failed` or `rolled_back`, NEVER `completed`. Build + tests green; `bash -n` clean on all three scenarios. `inject` import added to `exec.go` (was already in `service.go`).
- 2026-05-25 (Bug 2 PR opened independently of main branch arc): `release/bug-2-proxy-step11` branched off `origin/master` (`51670d9e1`); cherry-picked `ee8bba850` (RED) + `81018a495` (GREEN) preserving the TDD chronology. One conflict resolved in `service.go`'s step-11 error block (master's `d.rollback(...) + return err` pattern preserved; cherry-pick's parameterized `strings.Join` error message applied). Pushed as `7e54f7774` + `325c23b25`. PR https://github.com/statisticsnorway/statbus/pull/306 opened against master. `go build ./...` clean; `go test ./internal/upgrade/...` GREEN including the previously-RED `TestVersionTrackedAlignedWithUpgradePipeline`. Ships Bug 2 fix ahead of the larger Branch A harness bundle (which awaits scenario-26 empirical RED→GREEN confirmation from tester).
- 2026-05-25 (Bugs 1 + 2 TDD cycles, post mechanic's harness-canonical-invoke): `81018a495` — 58 commits ahead. Four commits in strict RED→GREEN pairs covering two independent bugs from `tmp/no-deploy-hang-summary-2026-05-25.md`. **Cycle 1 (Bug 1 — archiveBackup beyond ticker scope):** `69a67a5bc` adds inject class `archive-backup-stall-active-phase-watchdog` (KindStall) at the top of `archiveBackup` in `exec.go`, plus scenario 26 (`26-archivebackup-watchdog.sh`) driving via supervised systemd unit with STALL_HOLD_S=180s > WatchdogSec=120s and load-bearing NRestarts ≤ 1. RED on this commit. `b7ee2a0ca` widens the WATCHDOG=1 ticker to cover ALL of applyPostSwap's post-reconnect work via deferred cancel + reap; old d416a50a0 migrate-only ticker deleted (subsumed). Single-ticker shape chosen over per-step coverage because forward-resistant (future steps inherit coverage). **Cycle 2 (Bug 2 — versionTracked-vs-step-11 drift):** `ee8bba850` refactors versionTrackedServices + step11RestartServices into package vars (zero behavior change) and adds `TestVersionTrackedAlignedWithUpgradePipeline` in `containers_invariants_test.go`. Test fails RED because proxy is in versionTracked but missing from step 11. `81018a495` resolves via option (2) — add proxy to step11RestartServices (vs option 1 dropping it from versionTracked). Architectural argument: proxy carries Caddyfile/cert/port config that should refresh per upgrade; Caddy has no DB dependency; <2s restart impact on the maintenance page. Both bugs jointly explain rune.statbus.org's 2026-05-25 35-GB watchdog kill (Bug 1) + canary-wedge restart loop (Bug 2). Build green, full `go test ./internal/upgrade/...` green at tip, `bash -n` clean on scenario 26.
- 2026-05-23 (post C15 watchdog full-fire follow-up): `6db507fa0` — 54 commits ahead. Three-layer batch in one commit: (1) Race D fix — WATCHDOG=1 ticker wrapping `d.reconnect(ctx)` in applyPostSwap, mirroring the e6df084b7 migrate-ticker pattern; first ping fires immediately, then every 30s, stopped via cancel-context + explicit reaping of `tickerDone` before the error branch runs. (2) Harness helper — `fabricate_scheduled_upgrade_row(vm, head_sha)` in data-helpers.sh; INSERTs an `upgrade_state='scheduled'` row directly to bypass the unit's git-tag-based discover. Idempotent via ON CONFLICT (commit_sha) — transitions any prior state back to scheduled and clears conflicting lifecycle timestamps. Field choices follow service.go:2579's discover INSERT shape. (3) Scenario 19 promoted from diagnostic-only to full-fire — drives via supervised systemd-upgrade-service unit (stop → install drop-in → fabricate row → restart unit → wait for in_progress → hold STALL_HOLD_S=180s > WatchdogSec=120s → release file → wait for terminal → assert NRestarts delta ≤ 1). Side benefit: scenario 02 now uses `fabricate_scheduled_upgrade_row` too — fail-fast-on-missing-SHA path replaced; `./sb upgrade apply` failure on commit_tags mismatch is now non-fatal (the row is already scheduled, poll-tick picks it up).
- 2026-05-23 (post CI workflow / scope-a-ci-workflow task): `6b31741da` — 53 commits ahead. New file `.github/workflows/install-recovery-harness.yaml` triggers on `v*-rc.*` tag push + `workflow_dispatch` (with `scenarios` input for narrowing). Runs `./dev.sh test-install-recovery` against fresh Hetzner cx23s (one per scenario); uploads per-scenario logs; reaps orphan VMs on every exit. Wired into `./sb release stable` preflight as a 4th gate via `release.WorkflowInstallRecoveryHarness` constant + new `checkStableWorkflowGate(..., "install-recovery", ..., "SKIP_INSTALL_RECOVERY")` call. Long-help block + `doc/release-workflow-gates.md` table + bullet list updated. Activates the moment this branch merges to master. ~€0.13/run total (17 cx23 × €0.0072 minimum-billing). `go build ./...` + `go test ./internal/release/...` green; `yq` parses YAML clean.
- 2026-05-23 (post #150/#151/#152/#153 — FINAL scope-a scenario batch): `089a90951` — 51 commits ahead. Four scenarios + two new injection sites. Every named class in the inject registry now has a paired scenario.
    - `02-happy-upgrade.sh` (baseline — supervised unattended path). No inject site. install at v2026.05.2 → populate → snapshot → stage HEAD on disk → wait one upgrade-service discover tick → `./sb upgrade apply <HEAD-SHA>` (NOTIFY) → wait for state='completed'. Catches regressions in the unit's notify protocol (READY=1 / WATCHDOG=1) that inline `./sb install` scenarios would miss.
    - `23-between-migrations.sh` (C7) — new `inject.KillHere` inside `migrate.runUp`'s per-migration loop, AFTER the db.migration INSERT for N completes and BEFORE the next iteration begins runPsqlFile for N+1. Strict assertion: post-kill delta == 1 (proves the placement is between rather than before the INSERT). Pre-trigger precondition check verifies HEAD has ≥ 2 pending migrations past INSTALL_VERSION's baseline; if not, the scenario bails cleanly.
    - `24-rollback-kill.sh` (C9) — new `inject.KillHere` in `d.rollback()` between `restoreDatabase` and `docker compose up`. **DIAGNOSTIC ONLY** — firing depends on whether recovery's forward-recovery happens to fail (non-deterministic across HEAD's migration set). The scenario branches on the second-install exit code: 0 → forward-recovery succeeded (C9 not reached this run); 137 → C9 fired (third install completes the partial rollback). Both outcomes pass. Strict C9 firing-test would need a "force-forward-recovery-failure" injection class (analogous to the C15 watchdog full-fire follow-up).
    - `25-advisory-too-early.sh` (C16 / Race E) — KindExternal, no inject site. External orchestration: stop unit → `docker compose restart db` → immediately start unit → wait `RestartSec`+slack → assert unit reaches active + NRestarts delta ≤ 2. Non-deterministic race window: documents NRestarts=0 as a no-op (not a failure) and exposes `RACE_WINDOW_DELAY_S` for tuning.
    - Build + tests green; `bash -n` clean on all four scenarios.
