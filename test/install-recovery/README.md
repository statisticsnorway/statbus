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
./dev.sh test-install-recovery --keep-vm 5-install-seed-on-populated   # leave VM alive on failure (€0.17/day if forgotten)
```

**Prerequisite: CI images must exist on ghcr.io.** Each scenario installs StatBus by pulling `statbus-*:<commit_short>` images from ghcr.io. If the target commit's images have not been built and pushed by CI, the install fails with a pull error. Only run the harness against a commit whose images are green on ghcr.

**Battery freeze window (standing rule).** While a battery or arc run is in flight, no commits to scenario or arc files may land — the run's SHA is the tested SHA, and a mid-run commit makes the result unattributable. Land scenario changes BEFORE dispatching a run or BETWEEN runs, never during one. (Adopted from the STATBUS-044 campaign, where a mid-run board commit twice embedded untested code in the uploaded binary.)

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

## Scenario catalogue (19 scenarios)

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

> The three pre-swap kill covers moved to the **upgrade-arc-harness** (real register+schedule path, no fabricated `./sb install` dispatch): `preswap-backup-kill-arc` (C3 — abort, never `completed`), `preswap-binary-swap-kill-arc` (C5 — recoverFromFlag HEAD-match), `preswap-checkout-kill-arc` (C4 — `restoreGitState` to the old commit). The legacy `2-preswap-{backup,binary-swap,checkout}-kill` scenarios (and the earlier `2-preswap-checkout-kill-legacy`) were retired once their arcs went [PROVEN]. (STATBUS-071 §9(5) 5d.)

### 3-postswap — after the swap (migrate / restart / resume)

> The post-swap kill covers moved to the **upgrade-arc-harness** arcs (real register+schedule path): `postswap-between-migrations-kill-arc` (C7 — killed between migrations → in-dispatch forward-recovery → `completed`), `postswap-mid-migration-kill-arc` (C6 — killed before the first pending migration → forward-recovery), `postswap-mid-tx-kill-arc` (cell b — killed mid-tx before commit → aborts, re-applies → `completed`; the safe-case control), `postswap-after-commit-kill-arc` + `after-commit-before-recorded-kill-arc` (cell c — killed in the commit↔record gap → `rolled_back`, STATBUS-013/105), `postswap-container-restart-kill-arc` (C8 — `resumePostSwap` re-entry), `postswap-migration-timeout-arc` (C12 — watchdog keeps it alive → `completed`), `postswap-watchdog-reconnect-arc` (C15). The legacy `3-postswap-{between-migrations,mid-migration,mid-tx,container-restart,migration-timeout,watchdog-reconnect}-kill` scenarios were retired once their arcs went [PROVEN]. (STATBUS-071 §9(5) 5d.)

| Scenario | What it proves | Grounding |
|---|---|---|
| `3-postswap-migrate-killed-after-commit` | Killed in the ~ms window after a migration commits but before its `db.migration` row is recorded → re-run recovers (forward-then-restore) without double-applying. Retained pending architect review: its full normalized-dump `_assert_faithful_restore` + `UPGRADE_DIED_DURING_RESUME` error-match have no counterpart in `postswap-after-commit-kill-arc` yet. | StallHere primitives; STATBUS-017 (cell c) |
| `3-postswap-resume-died-parked` *(RETIRED — superseded by `postswap-health-park-arc`)* | **RETIRED (STATBUS-071 dead-producer carve-out; file deleted).** The fabricated D-class park (a hand-built resume killed twice at the SAME boot-migrate step → death budget parks) was the interim net for the park SUBSTRATE — park state, alive-idle NRestarts bounded+frozen, siren-once, flag present, never-`rolled_back`, parked-skip across extra restarts, un-park to a clean terminal. That substrate is now proven on the REAL path (register+schedule, no fabrication) by `postswap-health-park-arc` — a B-class at-target health-past-warmup park — **green on wave 10 (CI run 29171998401)**, which is the "deleted when the rebuild goes green" condition of STATBUS-071 comment #12. The scenario's ONE unique residue — the **D-class same-step-twice park decision** (the `boot-migrate` same-step reason + `recovery_attempts=3` exhaustion) — has no on-cue real-path construction under STATBUS-145's minimal-boot-migrate geometry, so it stays covered at the LOGIC level by `cli/internal/upgrade/recovery_escalation_test.go` (`TestResumeEscalation_BootMigrateSameStepTwice`, `TestResumeEscalation_SameStepTwiceParksEarly`, `…_BudgetExhaustDataSafeRollsBack`). | Superseded per STATBUS-071 comment #12. Original grounding retained for history: STATBUS-046/D3 crash-resume death budget (`resumeEscalation`, same-step-twice) hoisted to `RecoveryBudgetGuard`; STATBUS-131 AC#3 (`UPGRADE_CALLBACK` survives `sb config generate`). |
| `3-postswap-rune-wedge` | The rune shape, fabricated (in_progress row + service-held post_swap flag with a dead pid + a stale container set incl. a stale-but-SERVING proxy, exactly as rune had) with the old daemon left running → `./sb install` takes over (SIGKILL-class quiesce, never SIGTERM, flock-confirmed death), resumes forward, recreates the full service set incl. the stale proxy at the flag target, converges to `completed` with ZERO restores, removes the flag; a second install reads nothing-scheduled. The standing regression net for the one-shot live rune recovery (STATBUS-047). | STATBUS-039 takeover + forward-when-at-target; STATBUS-052 flock-confirmed quiesce; STATBUS-044 AC#1 (case 0 of the verdict matrix). The crash-LOOPING reclassify gate is deliberately not driven — a natural loop is extinct on HEAD by design (046 park budget); that gate stays unit-tested + rune-live-validated. v1 removed the proxy as a "harsher variant of stale" — refuted by its first run: the DB path routes THROUGH the proxy (Caddy layer4), so a missing proxy severs recovery's own connection (that finding has its own product ticket); rune's proxy was old but serving. |
| `3-postswap-worker-ddl-deadlock` | An upgrade whose migration needs a DDL lock the busy worker is holding → the installer must quiesce services first so the migration doesn't hang forever. | R1 quiesce-before-DDL (commit 02a144052); terminal within INSTALL_BUDGET_S |

> `3-postswap-migration-deterministic-error` was retired: an upgrade whose migration errors on every apply (cell e — genuinely unapplyable) is now covered by the **upgrade-arc-harness** failing arc (real V_fail → rollback → byte-identical clean-slate restore). (STATBUS-071 §9(5) 5d.)

> STATBUS-096's "eats all memory → OS kills it" coverage-map cell is exercised by the **upgrade-arc-harness** arc `postswap-migration-oom` (a real, running migration — `SELECT pg_sleep(60);` + a fixture table, bare, no fabrication — SIGKILLed via `docker compose kill` on its db container at a pg_stat_activity-confirmed midpoint, reproducing the OS OOM-killer's effect on Postgres deterministically; real memory pressure is forbidden as a trigger on the shared 4 GB harness VM, where the kernel's own OOM heuristics could take the daemon or sshd instead), **not** an install-recovery scenario: it needs the real register+schedule lineage the arc harness provides. Single-phase (no C/fixed phase) — terminal is `completed` (Run()'s own unconditional `EnsureDBUp` always revives the db before any recovery branch runs, so the killed migration always gets a live db back and completes forward on its re-attempt), fixture present, data intact. Best-effort legs: the STATBUS-017 boot-migrate fall-through line and STATBUS-109's db-unreachable backoff-retry marker (its first live firing in an arc), whichever path the run actually takes.
>
> STATBUS-095 piece 2's "runs past the ceiling → aborted" coverage-map cell is exercised by the **upgrade-arc-harness** arc `postswap-migration-ceiling` (a real, long-running migration — `SELECT pg_sleep(3600);`, bare — killed by OUR OWN internal `STATBUS_MIGRATE_UP_TIMEOUT` ceiling, armed via a systemd dropin + unit restart, contrast `postswap-migration-oom`'s external kill), **not** an install-recovery scenario. Unlike oom, nothing external ever revives anything here, so this IS a rollback story: terminal is `rolled_back`, V unrecorded, clean-slate fingerprint intact (the failing-arc apparatus applies verbatim), data intact. Asserts the named ceiling marker (`migration exceeded the ceiling (%s) — killed; rolling back`) and that the orphaned backend is reaped (the #14 leg).

### 4-rollback — during the built-in rollback

| Scenario | What it proves | Grounding |
|---|---|---|
| `4-rollback-abort-write-lands` | A rollback whose git-restore has no resolvable target (the true "r17" fabrication — direct state, no real executeUpgrade, so no `pre-upgrade` branch was ever pinned) aborts → the terminal write (`state=failed`) lands in ONE pass, ZERO kills, flag removed, unit alive-idle (NRestarts ≤ 1) — proving the box no longer loops forever writing its own terminal into a DB it just stopped. | STATBUS-136: `EnsureDBReachable`/`StartDBForRecovery` (`docker compose start db`) before the terminal write on `d.rollback()`'s git-corrupt ABORT branch; killed the r17 x3 death loop |

> The STATBUS-031 rollback-restore watchdog cover (a large-DB `rollback()` restore that outruns `WatchdogSec`) is exercised by the **upgrade-arc-harness** arc `postswap-rollback-restore-watchdog` (V_fail → rollback → restore-stall at `exec.go` `inject.StallHere("restore-db-stall-watchdog")`), **not** an install-recovery scenario: this harness installs release images and re-tags them via `stage-head.sh`, so it can't build the per-commit V_fail image the real-upgrade trigger needs. The former `4-rollback-restore-watchdog` scenario (a death-during-resume trigger, now self-heal-blocked) was retired. (STATBUS-071 §9(5) 5c-hard.)

> STATBUS-134's 2-consecutive-rollback-deaths restore-broke terminal is exercised by the **upgrade-arc-harness** arc `rollback-pair-terminal` (deterministic PreSwap-wedge entry — the same C5→C9 lineage as the `rollback-kill-arc` that reshaped the retired `4-rollback-kill` scenario — with a SECOND, re-armed C9 kill added so the on-disk `(rollback, rollback)` step pair forms and `rollbackResumeIsTerminal` fires `state=failed` before any third restore attempt), **not** an install-recovery scenario: it needs the real register+schedule lineage `rollback-kill-arc.sh` already proved deterministic. Deliberately a SEPARATE arc from `4-rollback-abort-write-lands` above — STATBUS-136's DB-start-before-write fix lives exclusively in the git-corrupt ABORT branch, structurally disjoint from this pair-terminal's (non-abort) kill site; one fabrication cannot exercise both (verified against shipped code, architect-ruled 2026-07-06).

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

`*(TBD)*` rows are scaffolded but not yet implemented. Full forensics + the complete C-class / R-tag priority map: `doc/archive/recovery-injection-scope-a-comprehensive.md` (2026-05 execution journal, archived — the CURRENT proof ledger is STATBUS-071's coverage map). Each `scenarios/<slug>.sh` header carries the complete per-scenario detail (inject site, expected behavior, status on current code).

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

## Probe conventions — PROBES OBSERVE, ASSERTS JUDGE; NO OBSERVATION WITHOUT A REASON (STATBUS-143)

A **probe** (a helper that reads VM state — a container state, a row column, a pid)
ALWAYS exits 0 and returns a *nameable* value. The **assert** — never the probe —
decides pass/fail, and it carries a **settle budget** wherever the expected state is
*eventual* rather than immediate.

The value a probe returns on failure MUST **name why it failed**. A bare `(unknown)`
is a dead end — it cost a full VM run (29212146524): a probe that demanded a running
proxy returned `(unknown)` on *every* poll for the whole settle budget, and the arc
log could not distinguish "the proxy genuinely isn't up" from "the probe's own remote
command is broken." The second turned out to be true and *deterministic*, not a
transient race — but the bare token hid that for an entire paid run. So:

- **`_probe` (lib/arc-helpers.sh) is the one channel for VM observation.** It runs a
  remote command, returns its stdout on success, and on ANY failure (transport OR
  command) returns `(unknown: <first stderr line, ≤120 chars, newline-stripped>)`. The
  reason is **bounded** and **single-line** because the value flows through `$(…)` and
  can reach a later `VM_EXEC` argument — a multi-line reason would re-open the quoting
  hazard class STATBUS-021 closed. The reason REPLACES any terminal `|| echo
  '(unknown)'`: a terminal echo swallows the remote command's non-zero exit and throws
  away the stderr that names it, fusing "state absent" with "probe broken."
- **State-demanding probes** (return a value the assert compares — a container state,
  a row column) call `_probe` and pass its value straight through. Under the arcs'
  `set -euo pipefail`, `_probe` never trips errexit inside `$(…)`; a failure surfaces
  as a named value one line before its own assertion, not an opaque `rc=1`.
- **Existence probes** ask a yes/no question, but keep the yes/no decision **local**
  (`svc=$(_probe "… ps -a --format '{{.Service}}'"); grep -qx proxy && echo yes || echo
  no`), so a broken remote command yields `(unknown: …)` instead of masquerading as a
  clean "no." Existence is immediate, so they still need no settle budget.
- **Probe the proven shape.** `proxy_state` reads running services with
  `docker compose ps --format '{{.Service}}'` — WITHOUT `-a`, so `ps` lists only running
  services by default, using ONLY the `.Service` template the severed sibling has always
  run GREEN. No new flag is introduced. The old two-field `--format '{{.Service}}
  {{.State}}'` form is what failed remotely; a probe reaches for the narrowest proven
  `docker compose` shape, not the richest one.
- **Settle budgets** (secondary, defense in depth): when the expected state arrives
  *after* the trigger (a container restart still finishing), poll the safe probe until
  it settles or a bounded budget expires, THEN assert. The wait establishes the
  precondition honestly — it does not weaken it: still running-or-refuse, just given the
  time the system genuinely needs. The reason-carrying probe, not the budget, is what
  diagnoses a *deterministic* failure — a budget only ever forgives a slow-but-real one.

The scar this codifies: `postswap-stopped-proxy-recovery-arc.sh` died `rc=1 at :140`,
then on re-run returned `(unknown)` for the FULL settle budget — proving the failure
was not a transient race but its own `proxy_state` probe: an `awk`-terminated
`--format '{{.Service}} {{.State}}'` pipeline whose remote `docker compose` invocation
failed deterministically, discarded behind `2>/dev/null || echo '(unknown)'`. Its GREEN
severed sibling survived the identical inject because its `proxy_present` probe used the
narrower `.Service`-only form. Both now route through `_probe`, so the next such failure
names itself in the arc log instead of costing a run to diagnose.

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
gh workflow run install-recovery-harness.yaml --ref master -f scenarios="0-happy-upgrade 5-install-seed-on-populated"
```
