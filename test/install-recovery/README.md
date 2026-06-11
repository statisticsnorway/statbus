# Install Recovery Test Harness

End-to-end Hetzner-Cloud regression tests for the install ladder's recovery surface. Sister to `./dev.sh test-install` (which validates only the happy path).

## Cost and prerequisites

The harness provisions **paid ephemeral [Hetzner Cloud](https://hetzner.cloud) VMs** (CX23, hel1, ~€0.0072/hr; Hetzner bills hourly with a 1-hour minimum, so a single scenario run costs at least €0.0072). `HCLOUD_TOKEN` must be set in `.env.credentials` before any run.

```bash
./dev.sh test-install-recovery                    # all scenarios (~90 min)
./dev.sh test-install-recovery 2-preswap          # all scenarios in a phase (phase prefix)
./dev.sh test-install-recovery bool-text          # by slug fragment
./dev.sh test-install-recovery --list             # show available
./dev.sh test-install-recovery --keep-vm 4-rollback-kill   # leave VM alive on failure (€0.17/day if forgotten)
```

**Prerequisite: CI images must exist on ghcr.io.** Each scenario installs StatBus by pulling `statbus-*:<commit_short>` images from ghcr.io. If the target commit's images have not been built and pushed by CI, the install fails with a pull error. Only run the harness against a commit whose images are green on ghcr.

## Why this exists

In a single session (rc.04 → rc.12), eleven recovery-related bugs shipped because we had no end-to-end test for the install ladder against deliberately wedged systems. The most embarrassing was Fix 11: a one-character `(...)::text` cast in `checkSessionsClean` that silently broke the function for three RCs (rc.09 / rc.10 / rc.11) — only caught because rune's wedged install kept failing.

A working install today should pass all scenarios in this harness. A regression that re-introduces any of fixes 6/7/8/9/10/11 will fail the corresponding scenario in <2 min after VM bootstrap.

Each scenario writes `tmp/install-recovery-<scenario>.log`. After all scenarios pass, the harness writes `tmp/install-recovery-test-passed-sha` (gateable by `./sb release stable --with-recovery-tests`).

## Architecture

```
test/install-recovery/
├── README.md                — this file
├── lib/
│   ├── vm-bootstrap.sh      — Hetzner Cloud VM provision + harden + statbus user
│   ├── wedge-helpers.sh     — simulate_* primitives (one per failure mode)
│   └── assertions.sh        — assert_* helpers (health, upgrade row, systemd, etc.)
├── scenarios/
│   └── NN-name.sh           — one scenario per file, individually runnable
└── run.sh                   — dispatcher
```

Each scenario is **a fresh Hetzner Cloud VM**, no state shared. Per-scenario isolation > shared-VM speed: bug-class regressions are caught reliably.

## Scenario catalogue

| Slug | Wedge simulated | Validates fixes |
|---|---|---|
| `0-happy-install` | None — fresh install only | Harness skeleton |
| `0-happy-upgrade` | Install at v2026.05.2 → populate → snapshot → stage HEAD on disk → wait one upgrade-service tick → `./sb upgrade apply <HEAD-SHA>` (NOTIFY) → wait for state='completed'. Supervised unattended path — the unit's discover + dispatch + executeUpgrade → applyPostSwap pipeline runs in production shape. | Baseline regression net for the happy upgrade. Catches regressions in unit notify protocol (READY=1, WATCHDOG=1) that the inline `./sb install` scenarios would miss. Load-bearing: state='completed' (anything else is a regression), data intact, NRestarts delta ≤ 2 (no watchdog/start-timeout fired). |
| `5-install-stage-a-killed-migrate` | SIGKILL a psql migrate-subprocess; orphan postgres backend | **Fix 3** Phase 1 cleanup; **Fix 1** prevents this in production; **Fix 5b** forward-recovery |
| `5-install-stage-b-pool-exhaustion` | Saturate `max_connections` with idle psql sessions | **Fix 3** docker-exec bypass when external connections fail |
| `5-install-stage-c-systemd-failed` | Trip StartLimitBurst (>10 starts in 600s) | **Fix 4** systemctl reset-failed in step 15 |
| `5-install-stage-d-advisory-zombie` | Open `pg_advisory_lock(migrate_up)` + SIGKILL the script | **Fix 6** Phase 2 PID-liveness + empty-app-name catch-all |
| `5-install-stage-e-worker-busy` | Queue heavy worker tasks; install while worker is processing | **Fix 8** worker excluded from advisory_holders count, **Fix 9** no false-fail on pool busy, **Fix 10** psql-only filter |
| `3-postswap-migrate-killed-after-commit` | Real SIGKILL during the canonical ~ms window (committed migration, `db.migration` row missing). Two stages: (1) kill the migrate subprocess → Layer 0 in-process `postSwapFailure` recovery; (2) kill the upgrade-service parent → Layer 2 next-install `recoverFromFlag` recovery. | Principled forward-then-restore (commit `fc5ae7cf7`), `inject.StallHere` primitives (`cli/internal/inject`), Layer 3 backup cleanup |
| `5-install-bool-text-regression` | Healthy install, re-run with worker active | **Fix 11** drop bool::text cast in checkSessionsClean |
| `5-install-seed-on-populated` *(C17 / R5 — DATA LOSS GRADE)* | Install at older release → populate demo data → switch sb binary + git tree to local HEAD → run install again. Forces the state-machine into "nothing-scheduled + migration tail mismatch", which on buggy code dispatches the destructive seed-restore against the populated DB. | Architectural — the install state machine MUST classify DB content (populated vs empty) before triggering the seed step. Load-bearing assertion: `assert_demo_data_present`. Validates the R5 classifier fix in commit `5dc66c237`. |
| `1-boot-concurrent-install` *(C10 / probe 2 live-upgrade refusal)* | First install reaches migrate.up and stalls via the existing `concurrent-install-attempted-during-migrate-up` site. While stalled, a second `./sb install` starts and must hit probe 2 (live-upgrade) detection and refuse with a clear diagnostic naming the holder PID. | Validates the install state-ladder's probe 2 refusal path. Load-bearing assertions: second install exits non-zero with diagnostic mentioning live-upgrade/holder/PID; exactly ONE row in `public.upgrade` (second install must not have inserted). |
| `3-postswap-migration-timeout` *(C12 / STATBUS-012 — boot-migrate vs watchdog)* | Install at older release → populate → stage HEAD → plant a synthetic pending migration → arm the C12 drop-in env **without restarting the unit** (env lands on the exit-42 post-swap restart) → fabricate scheduled row + NOTIFY wake. The upgrade's post-swap boot runs boot-migrate (`service.go:1644` — the site that consumes EVERY upgrade's migration delta); its `sb migrate up` child parks in `runPsqlFile`'s `StallHere` for `STALL_HOLD_S=180s` (> WatchdogSec=120s). Site-proof: the flag must read `post_swap` during the stall. | Validates the STATBUS-012 boot-migrate watchdog cover (always-ping `WATCHDOG=1` ticker + shared 30-min migrate timeout — design: backlog doc-005). Load-bearing assertions: `NRestarts` delta from the **post-stall baseline == 0** AND unit `Result ≠ watchdog` AND upgrade reaches `completed` after release. RED on the unfixed gap (SIGABRT kill-loop at ~120s). Rewritten 2026-06-11: the prior version dispatched inline (`./sb install` in tmux) — no systemd in the flow, no watchdog anywhere — and was vacuously green. |
| `3-postswap-worker-ddl-deadlock` *(C13 / R1 — most-damaging)* | Install at older release → populate demo data → start continuous worker workload (holds AccessShareLock on statistical_history) → run install at HEAD with new migrations applying DDL. Worker's lock blocks the migration's AccessExclusiveLock attempt; on current code the migration hangs indefinitely. | Architectural — the install state machine MUST quiesce services before DDL (R1 fix). Validates the R1 quiesce fix in commit `02a144052`. Load-bearing constraint: install reaches a terminal state within `INSTALL_BUDGET_S` (default 15 min); exit code 124 from `timeout(1)` is the wedge signal. |
| `3-postswap-container-restart-kill` *(C8 / state-bearing Layer 2 kill)* | Install at older release → populate → trigger upgrade with `STATBUS_INJECT_AT=killed-by-system-during-container-restart`. `inject.KillHere` fires inside `applyPostSwap` between step 11 (docker compose up worker/app/rest) and step 12 (health check). Containers in indeterminate state, flag PostSwap, migrations applied. Second install must complete the restart. | Validates the recoverFromFlag → resumePostSwap → applyPostSwap re-entry path. Load-bearing assertion: second install reaches state='completed' + assert_demo_data_present. |
| `2-preswap-binary-swap-kill` *(C5 / state-bearing Layer 2 kill)* | Install at older release → populate → trigger upgrade with `STATBUS_INJECT_AT=killed-by-system-during-binary-swap`. `inject.KillHere` fires inside `executeUpgrade` after `replaceBinaryOnDisk` but before `updateFlagPostSwap`. New binary on disk, flag PreSwap, migrations NOT applied. Second install must classify state and either forward-recover via migrate.Up or roll back via restoreBinary. | Validates recoverFromFlag's HEAD-matches branch handling Fix 5b's forward-recovery (or graceful rollback). Terminal state can be `completed` (forward succeeded) OR `rolled_back` (forward failed → restore) — both principled. Load-bearing: data intact regardless of branch. |
| `3-postswap-mid-migration-kill` *(C6 / Layer 2 atomic-tx retry)* | Install at older release → populate → trigger upgrade with `STATBUS_INJECT_AT=killed-by-system-during-individual-migration-execution`. `inject.KillHere` fires at the top of `migrate.runPsqlFile` BEFORE the psql subprocess runs the first pending migration. New binary, flag PostSwap, `db.migration` max_version UNCHANGED. Second install must retry the killed migration cleanly (the outer TX never opened → no partial state). | Validates forward-recovery via `recoverFromFlag` → `resumePostSwap` → `applyPostSwap` re-entry → `migrate.Up`. Load-bearing assertions: terminal state=`completed`, `db.migration` max_version BUMPED past baseline, data intact. |
| `1-boot-startup-timeout` *(C11 / Layer 1 — TimeoutStartSec fires)* | Install at HEAD. Write a systemd drop-in override on `statbus-upgrade@statbus.service` setting `STATBUS_INJECT_AT=service-startup-slower-than-systemd-unit-timeout` + release file + `TimeoutStopSec=5s` (keeps each restart cycle inside the test budget). Restart the unit. `inject.StallHere` fires in `Service.Run` AFTER the advisory lock and BEFORE `sdNotify("READY=1")`. systemd's static `TimeoutStartSec=120s` budget expires; SIGTERM + (5s later) SIGKILL terminate the process; NRestarts increments. Remove drop-in + release file; restart unit; verify it reaches `active`. | Validates the static-budget contract (commits f43b2bfd1, e6df084b7): no activating-phase extender, the unit IS killed when startup is slower than 120s, NRestarts stays bounded (≤ 2 = 1 timeout + 1 headroom). Operator recovery lever: `./sb install` (dispatches inline, bypassing the supervised unit's TimeoutStartSec). |
| `3-postswap-watchdog-reconnect` *(C15 / Race D — inject-site diagnostic)* | Install at older release → populate → trigger upgrade at HEAD with `STATBUS_INJECT_AT=service-watchdog-timeout-during-db-reconnect-after-container-restart` + release file. `inject.StallHere` fires inside `applyPostSwap` AFTER `waitForDBHealth` and BEFORE `d.reconnect(ctx)`. The install parks at the stall; harness releases the file; reconnect proceeds and the upgrade completes. | Validates that the C15 inject site is REACHABLE and surfaces the missing-coverage gap empirically — no `WATCHDOG=1` ticker currently wraps the reconnect block, so a supervised-unit dispatch with a slow reconnect would trip the watchdog. Does NOT actually fire the systemd watchdog (requires unit-dispatched upgrade, out of scope for this commit). Load-bearing: stall releases cleanly and the upgrade reaches `completed` with data intact. Fix shape (`WATCHDOG=1` ticker around reconnect, mirroring commit e6df084b7's migrate-ticker pattern) lands as a follow-up commit. |
| `1-boot-flag-stale-handoff` *(C14 / R3 — external orchestration)* | Bootstrap + install at INSTALL_VERSION normally → immediately snapshot `~/statbus/tmp/upgrade-in-progress.json` state → wait one upgrade-service tick → re-check. NO injection site fires (C14 is KindExternal). The scenario is a diagnostic for the R3 leak: an install that exits cleanly without releasing the flag, leaving the upgrade-service's stale-flag clear path as the convergence mechanism. | Surfaces the R3 leak empirically: if the flag is present immediately post-install, the leak is confirmed (current code); if absent, the principled-fix shape (install releases its own flag on clean exit) has landed. Either way the post-tick state MUST converge to flag-absent + services healthy. Fix shape: audit `install.go`'s `acquireOrBypass` exit paths so `ReleaseInstallFlag` runs on every exit (not just deferred). |
| `2-preswap-backup-kill` *(C3 / Layer 2 kill — backup phase)* | Install at older release → populate → snapshot → trigger upgrade at HEAD with `STATBUS_INJECT_AT=killed-by-system-during-preswap-backup`. `inject.KillHere` fires inside `backupDatabase` AFTER rsync finishes but BEFORE the atomic rename (`pre-upgrade-<stamp>.tmp` → `pre-upgrade-<stamp>`). Flag PreSwap, .tmp directory on disk with complete rsync contents (no final rename), OLD binary unswapped, OLD DB volume unmodified. Second install must abort cleanly via the PreSwap recovery branch. | Validates `recoverFromFlag`'s PreSwap branch handling — abort-without-commit. Terminal state must be `failed` or `rolled_back` (NEVER `completed` — the binary-swap boundary was not crossed). Load-bearing: .tmp directory cleaned up, ./sb still OLD, data intact (rsync was source-read-only). |
| `2-preswap-checkout-kill` *(C4 / Layer 2 kill — git checkout phase)* | Install at older release → populate → snapshot working-tree commit + ./sb version → trigger upgrade at HEAD with `STATBUS_INJECT_AT=killed-by-system-during-preswap-checkout`. `inject.KillHere` fires in `executeUpgrade` AFTER the internal `git checkout commitSHA` succeeds but BEFORE binary swap. Working tree at HEAD, backup .tmp dir possibly already finalized to its final name (backup phase ran upstream), ./sb still OLD, flag PreSwap. Second install must restore working tree via `restoreGitState`. | Validates `recoverFromFlag`'s PreSwap branch + `restoreGitState` via the pinned `pre-upgrade` branch. Terminal state must be `failed` or `rolled_back`. Load-bearing: working tree returns to the OLD commit (matches the post-initial-install snapshot), ./sb still OLD, data intact. |
| `3-postswap-between-migrations-kill` *(C7 / Layer 2 kill — between N and N+1)* | Install at v2026.05.2 → populate → snapshot data + baseline db.migration max_version → trigger upgrade at HEAD with `STATBUS_INJECT_AT=killed-by-system-between-migrations`. `inject.KillHere` fires inside `migrate.runUp`'s per-migration loop, AFTER the db.migration INSERT for migration N completes and BEFORE the next iteration begins runPsqlFile for N+1. Wedge: NEW binary, flag PostSwap, db.migration includes N but NOT N+1. Second install must apply remaining migrations cleanly via forward-recovery. | Validates `recoverFromFlag` → `resumePostSwap` → `applyPostSwap` re-entry → `migrate.Up` resume from the unrecorded pending set. Load-bearing: post-kill db.migration max_version bumped by exactly 1 (the recorded migration); post-recovery max_version bumped further (the remaining migrations applied); state='completed', data intact. |
| `4-rollback-kill` *(C9 / Layer 2 kill — diagnostic for rollback path)* | Install at v2026.05.2 → populate → snapshot → first install at HEAD with C5 env var (sets up wedge) → second install with `STATBUS_INJECT_AT=killed-by-system-during-builtin-rollback`. `inject.KillHere` site is placed in `d.rollback()` between `restoreDatabase` and `docker compose up`. Whether C9 actually FIRES depends on whether recovery's forward-recovery happens to fail (and falls through to `d.rollback()`) — non-deterministic. The scenario branches on the second install's exit code: 0 = forward-recovery succeeded (C9 not reached this run), 137 = C9 fired (third install completes the rollback). | DIAGNOSTIC ONLY — lands the C9 site at its principled placement; does NOT strictly assert C9 firing. Both outcomes pass as long as the system converges to a coherent terminal state (completed or rolled_back) with data intact. A strict C9 firing-test would need a "force-forward-recovery-failure" injection class (analogous to the C15 `3-postswap-watchdog-reconnect` follow-up). |
| `1-boot-advisory-too-early` *(C16 / Race E — external orchestration)* | Install at INSTALL_VERSION → stop the unit → `docker compose restart db` → immediately `systemctl --user start statbus-upgrade@statbus.service` (lands inside the "DB not yet accepting connections" window) → wait `RestartSec`+slack. NO injection site fires (C16 is KindExternal). systemd's `Restart=always` self-heals after the first failure (RestartForceExitStatus=42); the second start succeeds against a ready DB. | Validates the self-heal contract for Race E. Load-bearing: unit reaches `active` state, NRestarts delta ≤ 2 (the race triggers 1 restart + 1 headroom). NRestarts=0 means the race window was not hit this run — documented as a non-deterministic no-op, not a failure. |
| `3-postswap-archivebackup-resume` *(recovery-arc flaw — archiveBackup on the exit-42 RESUME; the NO/rune 40 h wedge)* | Install at INSTALL_VERSION → populate → snapshot + baseline NRestarts → stage HEAD. RUN 1: `./sb install` at HEAD with `STATBUS_INJECT_AT=killed-by-system-during-container-restart` → `inject.KillHere` exits 137 mid-`applyPostSwap`, leaving the flag pinned PostSwap + row `in_progress` (the resume precondition). RUN 2: install a drop-in pinning `STATBUS_INJECT_AT=archive-backup-stall-active-phase-watchdog` + release file + a SHORT `TimeoutStartSec` (inert post-fix; keeps pre-fix RED cycles fast) + restart the unit → the resume reaches `archiveBackup` and stalls. Hold past the WatchdogSec window, then release + assert convergence. | Closes the gap between `1-boot-startup-timeout` (generic pre-READY stall) and `3-postswap-archivebackup-watchdog` (archiveBackup stall in the ACTIVE phase): neither drove a real exit-42 RESUME whose `archiveBackup` blocks under systemd's timeout window. GREEN-asserting (post-fix, READY-before-resume + FIX A): the resume runs ACTIVE-phase (READY=1 fired before recoverFromFlag) so the WATCHDOG=1 ticker (a blind 30 s timer) keeps the unit alive across the stalled tar — 0 kills expected. The row reaches `completed` DURING the hold (FIX A: the terminal UPDATE + flag removal run BEFORE archiveBackup). NRestarts stays bounded (0 expected; ≤ 1 with jitter headroom). On a pre-fix binary (≤ branch base) it FAILS at the convergence checks — the row is stuck `in_progress` with NRestarts climbing at a cadence too slow to trip `StartLimitBurst` — which IS the reproduction of the NO wedge. |
| `5-install-drifted-unit-reconciled` *(unit-reconcile — heal stale systemd-unit config on a healthy host)* | Install at INSTALL_VERSION (healthy, unit active). Simulate drift: `sed` the deployed `statbus-upgrade@.service` to `WatchdogSec=infinity`/`TimeoutStartSec=90` (rune's stale shape), daemon-reload + restart so the RUNNING unit reflects it (RED precondition: `WatchdogUSec=infinity`). Run idempotent `./sb install`. | Validates the unit-reconcile fix: `checkServiceDone` now byte-compares the on-disk unit to the repo template (not just `is-active`), so a drifted HEALTHY box is detected; `runInstallService` rewrites the unit + daemon-reload + **restarts** it (a rewritten unit is inert until restart — `enable --now` doesn't restart a running unit). GREEN: on-disk unit byte-identical to repo template AND the RUNNING unit re-armed to repo timers (`WatchdogUSec`≠infinity, `TimeoutStartUSec`≈2min). CI-ONLY (needs real systemd); the byte-compare + re-arm wiring are covered locally by `TestUnitFileMatchesRepo_*` + `TestRunInstallService_RestartsOnDriftToArmTimers`. |

`*(TBD)*` = scaffolded but scenario logic not yet implemented.

Additional scenarios for forensics-surfaced classes (C3-C9, C11-C16, C18+) land per the priority order in `doc/recovery/recovery-injection-scope-a-comprehensive.md`. Each scenario file's header documents its C-class, R-tag, expected behavior, and known status on current code.

## Fix-to-scenario reverse mapping

When you regress a fix, here's what fails:

| Fix | Catches in scenario(s) |
|---|---|
| Fix 1 — sd_notify EXTEND_TIMEOUT | `5-install-stage-a-killed-migrate` (indirectly — without Fix 1 this scenario is more likely to recur) |
| Fix 2 — per-migration logging | All scenarios use `assert_step9_completed` (alias of `assert_step_database_sessions_completed`) which scans for `[N/M] Database sessions` lines by NAME (position/total wildcarded) |
| Fix 3 — cleanOrphanSessions docker-exec | `5-install-stage-a-killed-migrate`, `5-install-stage-b-pool-exhaustion`, `5-install-stage-d-advisory-zombie` |
| Fix 4 — systemctl reset-failed |
| Fix 5 — verifyUpgradeGroundTruth fail-loud + forward-recovery | `5-install-stage-a-killed-migrate` (forward-recovery completes the migration) |
| Fix 6 — application_name marker + Phase 2 advisory triage |
| Fix 7 — checkServicesDone docker compose ps positional | All scenarios (Fix 7's regression makes ALL installs short-circuit) |
| Fix 8 — checkSessionsClean exclude worker |
| Fix 9 — drop pool-saturation from checkSessionsClean |
| Fix 10 — application_name='psql' filter |
| Fix 11 — drop bool::text cast | `5-install-bool-text-regression` (and ALL scenarios — recheck-after-cleanup goes through this) |
| §4a FIX A — archiveBackup after the terminal `state='completed'` UPDATE + removeUpgradeFlag | `3-postswap-archivebackup-resume` (without it, a start-phase kill during the resume's tar cancels the DB context before the terminal UPDATE persists → row stuck `in_progress` → loop) + the local Go guard `TestArchiveBackupAfterTerminalUpdate` |
| unit-reconcile — `checkServiceDone` byte-compares the on-disk unit to the repo template; drift ⇒ rewrite + daemon-reload + restart | `5-install-drifted-unit-reconciled` (without it, a drifted unit on a healthy box is never rewritten — rune's stale 90/infinity persists) + the local Go guards `TestUnitFileMatchesRepo_*` (drift detection) + `TestRunInstallService_RestartsOnDriftToArmTimers` (re-arm) |

## Adding a new scenario

1. Create `scenarios/<phase>-<slug>.sh` — copy 0-happy-install.sh as a starting point.
   Phase prefix encodes WHEN in the upgrade timeline the wedge lands: `0-happy` (no wedge),
   `1-boot` (pre-READY / startup), `2-preswap` (before the binary+migration swap),
   `3-postswap` (after the swap, during migrate/restart/resume), `4-rollback`, `5-install`
   (the inline `./sb install` operator path). The slug is the canonical handle — the same
   string names the file, the runner, this table, the diagram TEST notes, and the code comments.
2. If you need a new wedge primitive, add it to `lib/wedge-helpers.sh` as a `simulate_*` function.
3. If you need a new assertion, add to `lib/assertions.sh` as `assert_*` returning 0 (pass) or 1 (fail).
4. Update this README's scenario table.

## Debugging a failing scenario

```bash
KEEP_VM=1 ./dev.sh test-install-recovery 5-install-bool-text-regression     # leave VM running on failure
multipass shell statbus-recovery-5-install-bool-text-regression             # connect interactively
multipass exec statbus-recovery-5-install-bool-text-regression -- sudo -i -u statbus
cd ~/statbus
./sb psql -c 'SELECT * FROM public.upgrade ORDER BY id DESC LIMIT 3;'
journalctl --user -u 'statbus-upgrade@*' --no-pager
```

Per-run install log is at `tmp/install-recovery-<vm_name>-install.log` on the host.

## Cleanup

VMs are deleted by `cleanup_vm` on scenario exit unless `KEEP_VM=1`. Manually:

```bash
multipass list                          # see what's running
multipass delete statbus-recovery-5-install-bool-text-regression    # delete by name
multipass purge                         # actually free disk
```

## CI integration

Not currently integrated — Multipass requires nested virtualization (VT-x/KVM) which most cloud CI runners don't expose. Local-dev tool initially. A self-hosted GitHub Actions runner with KVM access would unlock this.
