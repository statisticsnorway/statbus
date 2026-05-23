# Install Recovery Test Harness

End-to-end Multipass-based regression tests for the install ladder's recovery surface. Sister to `./dev.sh test-install` (which validates only the happy path).

## Why this exists

In a single session (rc.04 → rc.12), eleven recovery-related bugs shipped because we had no end-to-end test for the install ladder against deliberately wedged systems. The most embarrassing was Fix 11: a one-character `(...)::text` cast in `checkSessionsClean` that silently broke the function for three RCs (rc.09 / rc.10 / rc.11) — only caught because rune's wedged install kept failing.

A working install today should pass all scenarios in this harness. A regression that re-introduces any of fixes 6/7/8/9/10/11 will fail the corresponding scenario in <2 min after VM bootstrap.

## Running

```bash
./dev.sh test-install-recovery                    # all scenarios sequentially (~90 min)
./dev.sh test-install-recovery --list             # show available scenarios
./dev.sh test-install-recovery 09                 # just bool-text-regression (~10 min)
./dev.sh test-install-recovery 09 07              # multiple by number
./dev.sh test-install-recovery worker-busy        # by name substring
./dev.sh test-install-recovery --keep-vm 09       # leave VM running on failure (debug)
```

Each scenario writes `tmp/install-recovery-<scenario>.log`. After all scenarios pass, the harness writes `tmp/install-recovery-test-passed-sha` (gateable by `./sb release stable --with-recovery-tests`).

## Architecture

```
test/install-recovery/
├── README.md                — this file
├── lib/
│   ├── vm-bootstrap.sh      — multipass launch + harden + statbus user
│   ├── wedge-helpers.sh     — simulate_* primitives (one per failure mode)
│   └── assertions.sh        — assert_* helpers (health, upgrade row, systemd, etc.)
├── scenarios/
│   └── NN-name.sh           — one scenario per file, individually runnable
└── run.sh                   — dispatcher
```

Each scenario is **a fresh Multipass VM**, no state shared. Per-scenario isolation > shared-VM speed: bug-class regressions are caught reliably.

## Scenario catalogue

| # | Scenario | Wedge simulated | Validates fixes |
|---|---|---|---|
| 01 | `happy-install` | None — fresh install only | Harness skeleton |
| 02 | `happy-upgrade` | Install at v2026.05.2 → populate → snapshot → stage HEAD on disk → wait one upgrade-service tick → `./sb upgrade apply <HEAD-SHA>` (NOTIFY) → wait for state='completed'. Supervised unattended path — the unit's discover + dispatch + executeUpgrade → applyPostSwap pipeline runs in production shape. | Baseline regression net for the happy upgrade. Catches regressions in unit notify protocol (READY=1, WATCHDOG=1) that the inline `./sb install` scenarios would miss. Load-bearing: state='completed' (anything else is a regression), data intact, NRestarts delta ≤ 2 (no watchdog/start-timeout fired). |
| 03 | `stage-a-killed-migrate` | SIGKILL a psql migrate-subprocess; orphan postgres backend | **Fix 3** Phase 1 cleanup; **Fix 1** prevents this in production; **Fix 5b** forward-recovery |
| 04 | `stage-b-pool-exhaustion` | Saturate `max_connections` with idle psql sessions | **Fix 3** docker-exec bypass when external connections fail |
| 05 | `stage-c-systemd-failed` | Trip StartLimitBurst (>10 starts in 600s) | **Fix 4** systemctl reset-failed in step 15 |
| 06 | `stage-d-empty-app-advisory` | Open `pg_advisory_lock(migrate_up)` + SIGKILL the script | **Fix 6** Phase 2 PID-liveness + empty-app-name catch-all |
| 07 | `stage-e-worker-busy` | Queue heavy worker tasks; install while worker is processing | **Fix 8** worker excluded from advisory_holders count, **Fix 9** no false-fail on pool busy, **Fix 10** psql-only filter |
| 08 | `sigkill-canonical-layer2` | Real SIGKILL during the canonical ~ms window (committed migration, `db.migration` row missing). Two stages: (1) kill the migrate subprocess → Layer 0 in-process `postSwapFailure` recovery; (2) kill the upgrade-service parent → Layer 2 next-install `recoverFromFlag` recovery. | Principled forward-then-restore (commit `fc5ae7cf7`), `inject.StallHere` primitives (`cli/internal/inject`), Layer 3 backup cleanup |
| 09 | `bool-text-regression` | Healthy install, re-run with worker active | **Fix 11** drop bool::text cast in checkSessionsClean |
| 10 | `seed-on-populated` *(C17 / R5 — DATA LOSS GRADE)* | Install at older release → populate demo data → switch sb binary + git tree to local HEAD → run install again. Forces the state-machine into "nothing-scheduled + migration tail mismatch", which on buggy code dispatches the destructive seed-restore against the populated DB. | Architectural — the install state machine MUST classify DB content (populated vs empty) before triggering the seed step. Load-bearing assertion: `assert_demo_data_present`. Validates the R5 classifier fix in commit `5dc66c237`. |
| 11 | `concurrent-install` *(C10 / probe 2 live-upgrade refusal)* | First install reaches migrate.up and stalls via the existing `concurrent-install-attempted-during-migrate-up` site. While stalled, a second `./sb install` starts and must hit probe 2 (live-upgrade) detection and refuse with a clear diagnostic naming the holder PID. | Validates the install state-ladder's probe 2 refusal path. Load-bearing assertions: second install exits non-zero with diagnostic mentioning live-upgrade/holder/PID; exactly ONE row in `public.upgrade` (second install must not have inserted). |
| 12 | `migration-timeout` *(C12 / Race B regression net)* | Install at older release → populate demo data → trigger upgrade with `STATBUS_INJECT_AT=migration-slower-than-systemd-unit-timeout`. The migrate subprocess stalls inside `runPsqlFile` for `STALL_HOLD_S=180s` (> WatchdogSec=120s). With the WATCHDOG=1 ticker fix in `e6df084b7`, the parent stays alive; without it, the watchdog kills + restarts the unit (operator's dev: NRestarts=111). | Validates the Race B fix in commit `e6df084b7` (deleted `sdNotifyExtendTimeout`; ticker now sends `sdNotify("WATCHDOG=1")`). Load-bearing assertion: `NRestarts` delta during stall ≤ 2. |
| 13 | `worker-ddl-deadlock` *(C13 / R1 — most-damaging)* | Install at older release → populate demo data → start continuous worker workload (holds AccessShareLock on statistical_history) → run install at HEAD with new migrations applying DDL. Worker's lock blocks the migration's AccessExclusiveLock attempt; on current code the migration hangs indefinitely. | Architectural — the install state machine MUST quiesce services before DDL (R1 fix). Validates the R1 quiesce fix in commit `02a144052`. Load-bearing constraint: install reaches a terminal state within `INSTALL_BUDGET_S` (default 15 min); exit code 124 from `timeout(1)` is the wedge signal. |
| 15 | `container-restart-kill` *(C8 / state-bearing Layer 2 kill)* | Install at older release → populate → trigger upgrade with `STATBUS_INJECT_AT=killed-by-system-during-container-restart`. `inject.KillHere` fires inside `applyPostSwap` between step 11 (docker compose up worker/app/rest) and step 12 (health check). Containers in indeterminate state, flag PostSwap, migrations applied. Second install must complete the restart. | Validates the recoverFromFlag → resumePostSwap → applyPostSwap re-entry path. Load-bearing assertion: second install reaches state='completed' + assert_demo_data_present. |
| 16 | `binary-swap-kill` *(C5 / state-bearing Layer 2 kill)* | Install at older release → populate → trigger upgrade with `STATBUS_INJECT_AT=killed-by-system-during-binary-swap`. `inject.KillHere` fires inside `executeUpgrade` after `replaceBinaryOnDisk` but before `updateFlagPostSwap`. New binary on disk, flag PreSwap, migrations NOT applied. Second install must classify state and either forward-recover via migrate.Up or roll back via restoreBinary. | Validates recoverFromFlag's HEAD-matches branch handling Fix 5b's forward-recovery (or graceful rollback). Terminal state can be `completed` (forward succeeded) OR `rolled_back` (forward failed → restore) — both principled. Load-bearing: data intact regardless of branch. |
| 17 | `mid-migration-kill` *(C6 / Layer 2 atomic-tx retry)* | Install at older release → populate → trigger upgrade with `STATBUS_INJECT_AT=killed-by-system-during-individual-migration-execution`. `inject.KillHere` fires at the top of `migrate.runPsqlFile` BEFORE the psql subprocess runs the first pending migration. New binary, flag PostSwap, `db.migration` max_version UNCHANGED. Second install must retry the killed migration cleanly (the outer TX never opened → no partial state). | Validates forward-recovery via `recoverFromFlag` → `resumePostSwap` → `applyPostSwap` re-entry → `migrate.Up`. Load-bearing assertions: terminal state=`completed`, `db.migration` max_version BUMPED past baseline, data intact. |
| 18 | `startup-timeout` *(C11 / Layer 1 — TimeoutStartSec fires)* | Install at HEAD. Write a systemd drop-in override on `statbus-upgrade@test.service` setting `STATBUS_INJECT_AT=service-startup-slower-than-systemd-unit-timeout` + release file + `TimeoutStopSec=5s` (keeps each restart cycle inside the test budget). Restart the unit. `inject.StallHere` fires in `Service.Run` AFTER `checkMissedUpgrades` and BEFORE `sdNotify("READY=1")`. systemd's static `TimeoutStartSec=120s` budget expires; SIGTERM + (5s later) SIGKILL terminate the process; NRestarts increments. Remove drop-in + release file; restart unit; verify it reaches `active`. | Validates the static-budget contract (commits f43b2bfd1, e6df084b7): no activating-phase extender, the unit IS killed when startup is slower than 120s, NRestarts stays bounded (≤ 2 = 1 timeout + 1 headroom). Operator recovery lever: `./sb install` (dispatches inline, bypassing the supervised unit's TimeoutStartSec). |
| 19 | `watchdog-reconnect` *(C15 / Race D — inject-site diagnostic)* | Install at older release → populate → trigger upgrade at HEAD with `STATBUS_INJECT_AT=service-watchdog-timeout-during-db-reconnect-after-container-restart` + release file. `inject.StallHere` fires inside `applyPostSwap` AFTER `waitForDBHealth` and BEFORE `d.reconnect(ctx)`. The install parks at the stall; harness releases the file; reconnect proceeds and the upgrade completes. | Validates that the C15 inject site is REACHABLE and surfaces the missing-coverage gap empirically — no `WATCHDOG=1` ticker currently wraps the reconnect block, so a supervised-unit dispatch with a slow reconnect would trip the watchdog. Does NOT actually fire the systemd watchdog (requires unit-dispatched upgrade, out of scope for this commit). Load-bearing: stall releases cleanly and the upgrade reaches `completed` with data intact. Fix shape (`WATCHDOG=1` ticker around reconnect, mirroring commit e6df084b7's migrate-ticker pattern) lands as a follow-up commit. |
| 20 | `flag-stale-handoff` *(C14 / R3 — external orchestration)* | Bootstrap + install at INSTALL_VERSION normally → immediately snapshot `~/statbus/tmp/upgrade-in-progress.json` state → wait one upgrade-service tick → re-check. NO injection site fires (C14 is KindExternal). The scenario is a diagnostic for the R3 leak: an install that exits cleanly without releasing the flag, leaving the upgrade-service's stale-flag clear path as the convergence mechanism. | Surfaces the R3 leak empirically: if the flag is present immediately post-install, the leak is confirmed (current code); if absent, the principled-fix shape (install releases its own flag on clean exit) has landed. Either way the post-tick state MUST converge to flag-absent + services healthy. Fix shape: audit `install.go`'s `acquireOrBypass` exit paths so `ReleaseInstallFlag` runs on every exit (not just deferred). |
| 21 | `preswap-backup-kill` *(C3 / Layer 2 kill — backup phase)* | Install at older release → populate → snapshot → trigger upgrade at HEAD with `STATBUS_INJECT_AT=killed-by-system-during-preswap-backup`. `inject.KillHere` fires inside `backupDatabase` AFTER rsync finishes but BEFORE the atomic rename (`pre-upgrade-<stamp>.tmp` → `pre-upgrade-<stamp>`). Flag PreSwap, .tmp directory on disk with complete rsync contents (no final rename), OLD binary unswapped, OLD DB volume unmodified. Second install must abort cleanly via the PreSwap recovery branch. | Validates `recoverFromFlag`'s PreSwap branch handling — abort-without-commit. Terminal state must be `failed` or `rolled_back` (NEVER `completed` — the binary-swap boundary was not crossed). Load-bearing: .tmp directory cleaned up, ./sb still OLD, data intact (rsync was source-read-only). |
| 22 | `preswap-checkout-kill` *(C4 / Layer 2 kill — git checkout phase)* | Install at older release → populate → snapshot working-tree commit + ./sb version → trigger upgrade at HEAD with `STATBUS_INJECT_AT=killed-by-system-during-preswap-checkout`. `inject.KillHere` fires in `executeUpgrade` AFTER the internal `git checkout commitSHA` succeeds but BEFORE binary swap. Working tree at HEAD, backup .tmp dir possibly already finalized to its final name (backup phase ran upstream), ./sb still OLD, flag PreSwap. Second install must restore working tree via `restoreGitState`. | Validates `recoverFromFlag`'s PreSwap branch + `restoreGitState` via the pinned `pre-upgrade` branch. Terminal state must be `failed` or `rolled_back`. Load-bearing: working tree returns to the OLD commit (matches the post-initial-install snapshot), ./sb still OLD, data intact. |
| 23 | `between-migrations` *(C7 / Layer 2 kill — between N and N+1)* | Install at v2026.05.2 → populate → snapshot data + baseline db.migration max_version → trigger upgrade at HEAD with `STATBUS_INJECT_AT=killed-by-system-between-migrations`. `inject.KillHere` fires inside `migrate.runUp`'s per-migration loop, AFTER the db.migration INSERT for migration N completes and BEFORE the next iteration begins runPsqlFile for N+1. Wedge: NEW binary, flag PostSwap, db.migration includes N but NOT N+1. Second install must apply remaining migrations cleanly via forward-recovery. | Validates `recoverFromFlag` → `resumePostSwap` → `applyPostSwap` re-entry → `migrate.Up` resume from the unrecorded pending set. Load-bearing: post-kill db.migration max_version bumped by exactly 1 (the recorded migration); post-recovery max_version bumped further (the remaining migrations applied); state='completed', data intact. |
| 24 | `rollback-kill` *(C9 / Layer 2 kill — diagnostic for rollback path)* | Install at v2026.05.2 → populate → snapshot → first install at HEAD with C5 env var (sets up wedge) → second install with `STATBUS_INJECT_AT=killed-by-system-during-builtin-rollback`. `inject.KillHere` site is placed in `d.rollback()` between `restoreDatabase` and `docker compose up`. Whether C9 actually FIRES depends on whether recovery's forward-recovery happens to fail (and falls through to `d.rollback()`) — non-deterministic. The scenario branches on the second install's exit code: 0 = forward-recovery succeeded (C9 not reached this run), 137 = C9 fired (third install completes the rollback). | DIAGNOSTIC ONLY — lands the C9 site at its principled placement; does NOT strictly assert C9 firing. Both outcomes pass as long as the system converges to a coherent terminal state (completed or rolled_back) with data intact. A strict C9 firing-test would need a "force-forward-recovery-failure" injection class (analogous to #163's C15 follow-up). |
| 25 | `advisory-too-early` *(C16 / Race E — external orchestration)* | Install at INSTALL_VERSION → stop the unit → `docker compose restart db` → immediately `systemctl --user start statbus-upgrade@test.service` (lands inside the "DB not yet accepting connections" window) → wait `RestartSec`+slack. NO injection site fires (C16 is KindExternal). systemd's `Restart=always` self-heals after the first failure (RestartForceExitStatus=42); the second start succeeds against a ready DB. | Validates the self-heal contract for Race E. Load-bearing: unit reaches `active` state, NRestarts delta ≤ 2 (the race triggers 1 restart + 1 headroom). NRestarts=0 means the race window was not hit this run — documented as a non-deterministic no-op, not a failure. |

`*(TBD)*` = scaffolded but scenario logic not yet implemented.

Additional scenarios for forensics-surfaced classes (C3-C9, C11-C16, C18+) land per the priority order in `~/.claude-veridit/plans/recovery-injection-scope-a-comprehensive.md`. Each scenario file's header documents its C-class, R-tag, expected behavior, and known status on current code.

## Fix-to-scenario reverse mapping

When you regress a fix, here's what fails:

| Fix | Catches in scenario(s) |
|---|---|
| Fix 1 — sd_notify EXTEND_TIMEOUT | 03 (indirectly — without Fix 1 this scenario is more likely to recur) |
| Fix 2 — per-migration logging | All scenarios use `assert_step9_completed` which scans for `[N/15]` lines |
| Fix 3 — cleanOrphanSessions docker-exec | 03, 04, 06 |
| Fix 4 — systemctl reset-failed | 05 |
| Fix 5 — verifyUpgradeGroundTruth fail-loud + forward-recovery | 03 (forward-recovery completes the migration) |
| Fix 6 — application_name marker + Phase 2 advisory triage | 06 |
| Fix 7 — checkServicesDone docker compose ps positional | All scenarios (Fix 7's regression makes ALL installs short-circuit) |
| Fix 8 — checkSessionsClean exclude worker | 07 |
| Fix 9 — drop pool-saturation from checkSessionsClean | 07 |
| Fix 10 — application_name='psql' filter | 07 |
| Fix 11 — drop bool::text cast | 09 (and ALL scenarios — recheck-after-cleanup goes through this) |

## Adding a new scenario

1. Create `scenarios/NN-slug.sh` — copy 01-happy-install.sh as a starting point.
2. If you need a new wedge primitive, add it to `lib/wedge-helpers.sh` as a `simulate_*` function.
3. If you need a new assertion, add to `lib/assertions.sh` as `assert_*` returning 0 (pass) or 1 (fail).
4. Update this README's scenario table.

## Debugging a failing scenario

```bash
KEEP_VM=1 ./dev.sh test-install-recovery 09     # leave VM running on failure
multipass shell statbus-recovery-09             # connect interactively
multipass exec statbus-recovery-09 -- sudo -i -u statbus
cd ~/statbus
./sb psql -c 'SELECT * FROM public.upgrade ORDER BY id DESC LIMIT 3;'
journalctl --user -u 'statbus-upgrade@*' --no-pager
```

Per-run install log is at `tmp/install-recovery-<vm_name>-install.log` on the host.

## Cleanup

VMs are deleted by `cleanup_vm` on scenario exit unless `KEEP_VM=1`. Manually:

```bash
multipass list                          # see what's running
multipass delete statbus-recovery-09    # delete by name
multipass purge                         # actually free disk
```

## CI integration

Not currently integrated — Multipass requires nested virtualization (VT-x/KVM) which most cloud CI runners don't expose. Local-dev tool initially. A self-hosted GitHub Actions runner with KVM access would unlock this.
