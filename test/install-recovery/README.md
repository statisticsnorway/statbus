# Install Recovery Test Harness

> **Read first: [The only way to know if install and upgrade work is to run them](../../doc/install-upgrade-testing.md).**
> You cannot reason out whether these paths work — the problem is too hard. The only way to know is commit → push → CI builds the per-commit image → run it on a real VM here → observe → iterate. Unlike the SQL, Go, and integration tests, these *cannot* be run before you push. Stalling before a run produces zero knowledge.

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

## What every scenario proves (the one goal, in plain words)

Operators of StatBus have exactly one recovery lever: re-run `./sb install`. They never run custom commands. So every scenario in this harness proves the same single thing:

> **If the machine dies at a specific dangerous moment during an install or upgrade, then re-running `./sb install` — and nothing else — must bring the system back to a coherent state, with all data intact.**

Each scenario picks one such moment (the machine is killed mid-backup, mid-git-checkout, mid-binary-swap, mid-migration, mid-rollback, …), then checks that the plain operator re-run recovers. Read each scenario as: **"die HERE → the operator's re-run must end up THERE (a named terminal state) with data intact."** The internal codes (C3, R5, "Fix 11", inject-class names) are grounding for the engineer; the goal above is what the test is *for*.

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

## Scenario catalogue (32 scenarios)

Every entry leads with its **plain goal** — read it as **die HERE → the operator's `./sb install` re-run must end at THIS terminal state, data intact.** The goal is what the test is *for*; the *Grounding* column is the mechanism (inject site, C-class, the fix it guards) for the engineer. The full per-scenario detail lives in each `scenarios/<slug>.sh` header. The **phase prefix** says *when* in the timeline the wedge lands: `0` happy · `1-boot` pre-READY/startup · `2-preswap` before the binary+migration swap · `3-postswap` after the swap (migrate/restart/resume) · `4-rollback` during the built-in rollback · `5-install` the inline `./sb install` operator path.

### 0 — happy paths (no wedge)

| Scenario | What it proves | Grounding |
|---|---|---|
| `0-happy-install` | A fresh install just works — the harness baseline. | No wedge; harness skeleton |
| `0-happy-upgrade` | A normal unattended upgrade (v2026.05.2 → HEAD via the upgrade service) completes, data intact, with no watchdog or unexpected restart firing. | Supervised unit notify path (READY=1 / WATCHDOG=1) the inline scenarios miss; load-bearing: state=`completed`, NRestarts delta ≤ 2 |

### 1-boot — pre-READY / startup

| Scenario | What it proves | Grounding |
|---|---|---|
| `1-boot-advisory-too-early` | The upgrade unit starts before the DB is accepting connections → systemd self-heals and the next start succeeds. | `Restart=always` + RestartForceExitStatus=42 (C16); NRestarts ≤ 2 |
| `1-boot-concurrent-install` | A second `./sb install` launched while one is mid-migration → it refuses with a clear "live upgrade in progress" diagnostic naming the holder PID, and inserts no second row. | Install probe-2 (live-upgrade) refusal (C10) |
| `1-boot-flag-stale-handoff` | An install that exits cleanly without releasing its in-progress flag → the upgrade service's stale-flag path converges (flag gone, services healthy). | R3 leak diagnostic; fix = release the flag on every exit |
| `1-boot-startup-timeout` | An upgrade that starts up slower than systemd's 120 s timeout → the unit IS killed (bounded restarts), and the operator's `./sb install` still recovers. | Static TimeoutStartSec contract, no activating-phase extender (C11); NRestarts ≤ 2 |

### 2-preswap — before the binary + migration swap

| Scenario | What it proves | Grounding |
|---|---|---|
| `2-preswap-backup-kill` | Killed mid-backup, before the atomic rename → re-run aborts cleanly (terminal `failed`/`rolled_back`, **never** `completed` — the swap boundary wasn't crossed), `.tmp` cleaned up, data intact. | inject.KillHere in `backupDatabase` after rsync, before rename; PreSwap abort branch (C3) |
| `2-preswap-binary-swap-kill` | Killed after the new binary is on disk but before the swap is recorded → re-run either forward-recovers or rolls back cleanly; either way data intact. | inject.KillHere after `replaceBinaryOnDisk`; recoverFromFlag HEAD-match (C5, Fix 5b) |
| `2-preswap-checkout-kill` | Killed after the internal git checkout but before the binary swap → re-run restores the working tree to the old commit (via the pinned `pre-upgrade` branch), still old binary, data intact. | inject.KillHere after `git checkout`; `restoreGitState` (C4) |

> `2-preswap-checkout-kill-legacy` was retired: the reshaped `2-preswap-checkout-kill` (post-086) supersedes it. (STATBUS-071 §9(5) 5d.)

### 3-postswap — after the swap (migrate / restart / resume)

| Scenario | What it proves | Grounding |
|---|---|---|
| `3-postswap-between-migrations-kill` | Killed between migration N and N+1 → re-run applies the remaining migrations cleanly (resume from the recorded point), data intact. | inject.KillHere in `migrate.runUp` loop; forward-recovery (C7) |
| `3-postswap-container-restart-kill` | Killed mid-container-restart after migrations applied → re-run completes the restart, data intact. | inject.KillHere in `applyPostSwap`; `resumePostSwap` re-entry (C8) |
| `3-postswap-mid-migration-kill` | Killed just before the first pending migration runs → re-run retries it cleanly (the outer tx never opened → no partial state). | inject.KillHere at top of `runPsqlFile`; atomic-tx retry (C6) |
| `3-postswap-mid-tx-kill` | Killed mid-migration, *before* its transaction commits → Postgres aborts the tx (cleanly pending again), re-run re-applies and reaches `completed`, data intact. The **safe-case control** for the commit↔record boundary. | Test-only mid-tx inject (cell b); contrast the STATBUS-017 wedge |
| `3-postswap-migrate-killed-after-commit` | Killed in the ~ms window after a migration commits but before its `db.migration` row is recorded → re-run recovers (forward-then-restore) without double-applying. | StallHere primitives; STATBUS-017 (cell c) |
| `3-postswap-migration-timeout` | A post-swap migration that runs longer than the watchdog window → the unit keeps it alive (no SIGABRT kill-loop) and the upgrade reaches `completed`. | STATBUS-012 boot-migrate watchdog cover (WATCHDOG=1 ticker + 30-min timeout) |
| `3-postswap-resume-died-parked` | A fabricated resume (in_progress row + service-held post_swap flag, no dispatch/claim involved) killed twice at the SAME step (boot-migrate, the resume-time schema catch-up that runs BEFORE recoverFromFlag) across two crash-resumes → the death budget PARKS the upgrade (alive-idle, NRestarts bounded+frozen, siren fires exactly once via a `.env.config`-only `UPGRADE_CALLBACK`, never `rolled_back`) instead of looping loud forever or rolling back; a deliberate `./sb install` un-parks it for exactly one fresh attempt, which completes. | STATBUS-046/D3 crash-resume death budget (`resumeEscalation`, same-step-twice) hoisted to `RecoveryBudgetGuard` (STATBUS-044 comment #6, commit cc660280f) so boot-migrate deaths self-count; STATBUS-131 AC#3 (`UPGRADE_CALLBACK` survives `sb config generate`). Renamed/rebuilt from the deleted `3-postswap-resume-died-rollback` (STATBUS-099) — that shape predates the death budget and asserted rollback, which the new mechanism no longer produces at-target. Rebuilt a second time (STATBUS-044 comment #6) after the 12-run park-oracle campaign proved the original migrate-up construction targeted an unreachable resume-time window. |
| `3-postswap-rune-wedge` | The rune shape, fabricated (in_progress row + service-held post_swap flag with a dead pid + stale container set + the proxy REMOVED entirely) with the old daemon left running → `./sb install` takes over (SIGKILL-class quiesce, never SIGTERM, flock-confirmed death), resumes forward, recreates the full service set incl. the proxy at the flag target, converges to `completed` with ZERO restores, removes the flag; a second install reads nothing-scheduled. The standing regression net for the one-shot live rune recovery (STATBUS-047). | STATBUS-039 takeover + forward-when-at-target; STATBUS-052 flock-confirmed quiesce; STATBUS-044 AC#1 (case 0 of the verdict matrix). The crash-LOOPING reclassify gate is deliberately not driven — a natural loop is extinct on HEAD by design (046 park budget); that gate stays unit-tested + rune-live-validated. |
| `3-postswap-watchdog-reconnect` | An upgrade that stalls reconnecting to the DB after a container restart → confirms the inject site is reachable, surfacing the missing watchdog cover there. | inject.StallHere after `waitForDBHealth`, before `reconnect` (C15); fix = WATCHDOG ticker, follow-up |
| `3-postswap-worker-ddl-deadlock` | An upgrade whose migration needs a DDL lock the busy worker is holding → the installer must quiesce services first so the migration doesn't hang forever. | R1 quiesce-before-DDL (commit 02a144052); terminal within INSTALL_BUDGET_S |

> `3-postswap-migration-deterministic-error` was retired: an upgrade whose migration errors on every apply (cell e — genuinely unapplyable) is now covered by the **upgrade-arc-harness** failing arc (real V_fail → rollback → byte-identical clean-slate restore). (STATBUS-071 §9(5) 5d.)

### 4-rollback — during the built-in rollback

| Scenario | What it proves | Grounding |
|---|---|---|
| `4-rollback-kill` | Killed during the built-in rollback → the system still converges to a coherent terminal state (`completed` or `rolled_back`), data intact. | inject.KillHere in `d.rollback()` (C9); fires non-deterministically — diagnostic for the rollback path |

> The STATBUS-031 rollback-restore watchdog cover (a large-DB `rollback()` restore that outruns `WatchdogSec`) is exercised by the **upgrade-arc-harness** arc `postswap-rollback-restore-watchdog` (V_fail → rollback → restore-stall at `exec.go` `inject.StallHere("restore-db-stall-watchdog")`), **not** an install-recovery scenario: this harness installs release images and re-tags them via `stage-head.sh`, so it can't build the per-commit V_fail image the real-upgrade trigger needs. The former `4-rollback-restore-watchdog` scenario (a death-during-resume trigger, now self-heal-blocked) was retired. (STATBUS-071 §9(5) 5c-hard.)

### 5-install — the inline `./sb install` operator path

| Scenario | What it proves | Grounding |
|---|---|---|
| `5-install-bool-text-regression` | Re-run a healthy install with the worker active → the session-clean check doesn't misfire on a spurious bool→text cast. | Fix 11 (drop the `(...)::text` cast in `checkSessionsClean`) |
| `5-install-drifted-unit-reconciled` | Re-install on a *healthy* box whose systemd unit config has DRIFTED → the installer detects it (byte-compares the on-disk unit to the repo template) and rewrites + restarts the unit to re-arm the timers. | unit-reconcile fix; `checkServiceDone` byte-compare (a rewritten unit is inert until restart) |
| `5-install-seed-on-populated` *(DATA-LOSS GRADE)* | Re-install over a POPULATED DB → the installer classifies it as populated and **never** runs the destructive seed-restore. | R5 content classifier (commit 5dc66c237); load-bearing: `assert_demo_data_present` |
| `5-install-stage-a-killed-migrate` | Killed during a migrate subprocess (orphaned postgres backend) → re-run cleans up and completes, data intact. | Fix 3 Phase-1 cleanup + Fix 5b forward-recovery (Fix 1 prevents it in production) |
| `5-install-stage-b-pool-exhaustion` | Install while all DB connections are exhausted → install still proceeds (via the docker-exec bypass). | Fix 3 docker-exec when external connections fail |
| `5-install-stage-c-systemd-failed` | Install after the unit tripped systemd's start-limit (>10 starts / 600 s) → re-run resets the failed unit and proceeds. | Fix 4 `systemctl reset-failed` |
| `5-install-stage-d-advisory-zombie` | Install with a *dead* process still holding the migrate advisory lock → re-run detects the zombie (PID-liveness) and proceeds. | Fix 6 PID-liveness + empty-app-name catch-all |
| `5-install-stage-e-worker-busy` | Install while the worker is busy processing → install isn't fooled into a false "busy" failure. | Fix 8 (worker excluded from holders) / Fix 9 (no pool-busy false-fail) / Fix 10 (psql-only filter) |

`*(TBD)*` rows are scaffolded but not yet implemented. Full forensics + the complete C-class / R-tag priority map: `doc/recovery/recovery-injection-scope-a-comprehensive.md`. Each `scenarios/<slug>.sh` header carries the complete per-scenario detail (inject site, expected behavior, status on current code).

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
4. Update this README's scenario catalogue — lead the new entry with its plain goal (die HERE → re-run ends THERE, data intact), mechanism as grounding.

## Debugging a failing scenario

Re-run with `--keep-vm` so the scenario's **Hetzner VM** survives the failure (it keeps billing ~€0.0072/hr until you delete it). The harness prints the exact connect commands on exit; in general, for VM `statbus-recovery-<slug>`:

```bash
./dev.sh test-install-recovery --keep-vm 5-install-bool-text-regression
ip=$(hcloud server ip statbus-recovery-5-install-bool-text-regression)   # the VM's IP
ssh root@$ip                                   # root shell
ssh statbus@$ip                                # the statbus service user (cd ~/statbus)
ssh root@$ip 'sudo -i -u statbus -- ./sb psql -c "SELECT * FROM public.upgrade ORDER BY id DESC LIMIT 3;"'
ssh root@$ip journalctl --user -u 'statbus-upgrade@*' --no-pager -n 200
```

Each scenario's full log is uploaded as a CI artifact `install-recovery-log-<slug>` (`gh run download <run-id> -n install-recovery-log-<slug>`) and written locally to `tmp/install-recovery-<vm_name>.log`.

## Cleanup

VMs are deleted by `cleanup_vm` on scenario exit unless `--keep-vm` (`KEEP_VM=1`). Manually:

```bash
hcloud server list                                                       # see what's running
hcloud server list -o columns=name | grep '^statbus-recovery-'           # just this harness's VMs
hcloud server delete statbus-recovery-5-install-bool-text-regression     # delete by name
```

A VM left running by `--keep-vm` bills ~€0.17/day until deleted.

## CI integration

CI-integrated via `.github/workflows/install-recovery-harness.yaml` — it runs the full scenario matrix on **Hetzner Cloud VMs** (one fresh VM per scenario; `max-parallel` bounded by the Hetzner quota), on prerelease-tag push (`v*-rc.*`) and manual dispatch. Each scenario pulls the per-commit `statbus-*:<commit_short>` images built by `images.yaml`, so the target commit's images must be green on ghcr first. The stable-release pre-flight gates on a green run via `release.CheckWorkflowAtCommit(WorkflowInstallRecoveryHarness, sha)`.

```bash
gh workflow run install-recovery-harness.yaml --ref master                                   # all scenarios (blank = all)
gh workflow run install-recovery-harness.yaml --ref master -f scenarios="2-preswap-backup-kill 4-rollback-kill"
```
