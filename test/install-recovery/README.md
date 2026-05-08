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
| 02 | `happy-upgrade` | Install older RC, schedule upgrade via NOTIFY *(TBD)* | Normal upgrade-service path |
| 03 | `stage-a-killed-migrate` | SIGKILL a psql migrate-subprocess; orphan postgres backend | **Fix 3** Phase 1 cleanup; **Fix 1** prevents this in production; **Fix 5b** forward-recovery |
| 04 | `stage-b-pool-exhaustion` | Saturate `max_connections` with idle psql sessions | **Fix 3** docker-exec bypass when external connections fail |
| 05 | `stage-c-systemd-failed` | Trip StartLimitBurst (>10 starts in 600s) | **Fix 4** systemctl reset-failed in step 15 |
| 06 | `stage-d-empty-app-advisory` | Open `pg_advisory_lock(migrate_up)` + SIGKILL the script | **Fix 6** Phase 2 PID-liveness + empty-app-name catch-all |
| 07 | `stage-e-worker-busy` | Queue heavy worker tasks; install while worker is processing | **Fix 8** worker excluded from advisory_holders count, **Fix 9** no false-fail on pool busy, **Fix 10** psql-only filter |
| 08 | `stage-f-sigkill-mid-upgrade` *(TBD)* | `kill -9` upgrade-service Go process mid-migrate | Layer 1 (signal handler), Layer 2 (`--recovery=auto`), Layer 3 (orphan backup cleanup) |
| 09 | `bool-text-regression` | Healthy install, re-run with worker active | **Fix 11** drop bool::text cast in checkSessionsClean |
| 10 | `stage-g-non-idempotent-migration` *(TBD)* | Custom migration with side-effects, SIGKILL mid-flight | Layer 2's `--recovery=auto` heuristic |

`*(TBD)*` = scaffolded but scenario logic not yet implemented (depends on Layer 2 of the rollback-hole plug).

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
