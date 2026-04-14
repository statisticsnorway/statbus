# Upgrade System

The canonical reference for how StatBus upgrades itself. Three orchestration paths exist; they must never fight each other. The mutex contract described here is enforced in code so that running a manual install while the service is mid-upgrade fails loud with a diagnostic, rather than corrupting state.

## Three orchestration paths

| Path | Entry point | Owns | Respects | When to use |
|---|---|---|---|---|
| **Service** (automatic) | `./sb upgrade service` running as systemd user unit `statbus-upgrade@<slot>.service` | End-to-end upgrade lifecycle: discover → schedule → execute → recover | Its own advisory lock, its own flag file | Production norm. Discovers and applies releases on a 6-hour cycle or on NOTIFY. |
| **Manual install** | `./sb install` | Step-by-step repair of a single host (Prerequisites, Repository, Binary, Config, …, Migrations, …, Upgrade service) | The service's mutex flag — refuses to run if a real upgrade is in flight | First-time install or when an operator needs to repair a specific host. |
| **Cloud tool** | `./cloud.sh install <server>` | Fleet-level remote install: SSH + stop service + run install + start service | Its own fleet semantics; defers to the service/install mutex for per-host safety | Operator updating a remote host from their own machine. |

GitHub Actions workflows (`deploy-to-<slot>.yaml`) trigger the service path — they run `./sb upgrade apply-latest` remotely, which sends a NOTIFY that the service picks up. Actions never call `./sb install` directly.

## Flag-file state machine

The upgrade service writes `~/statbus/tmp/upgrade-in-progress.json` before any destructive step (`service.go:writeUpgradeFlag`). The flag file is the single source of truth for "is an orchestrated upgrade in flight or crashed pending recovery".

Two formal states:

| State | Flag present | Meaning |
|---|---|---|
| **Idle** | no | Nothing orchestrated. Any caller (service, install, cloud.sh) can proceed. |
| **InProgress** | yes | Either a live upgrade is running OR a prior one crashed and needs recovery. |

Inside InProgress, the flag carries a PID and `pidAlive(PID)` acts as a **diagnostic subquery** that selects between two messages:
- PID alive → "upgrade in progress — wait for it"
- PID dead → "upgrade crashed — start the service to recover"

This is not a third state: it's an explanation for why the same InProgress state blocks the caller.

### Flag schema (`UpgradeFlag` in `cli/internal/upgrade/service.go`)

```go
type UpgradeFlag struct {
    ID          int       `json:"id"`           // public.upgrade.id
    CommitSHA   string    `json:"commit_sha"`   // target commit
    DisplayName string    `json:"display_name"` // tag or sha-prefix
    PID         int       `json:"pid"`          // os.Getpid() at write
    StartedAt   time.Time `json:"started_at"`
    InvokedBy   string    `json:"invoked_by"`   // e.g. "scheduled", "recovery"
    Trigger     string    `json:"trigger"`      // coarse bucket for logs
}
```

### Cleanup paths (all must remove the flag)

| Path | Location |
|---|---|
| Normal completion | `executeUpgrade` end, `service.go` |
| Rollback on failure | end of `rollback()`, `service.go` |
| Self-update restart recovery (success) | `recoverFromFlag`, `service.go:~150` |
| Crash recovery (failure) | `recoverFromFlag`, `service.go:~180` |
| completeInProgressUpgrade | `service.go` |

If any new code path writes the flag, it MUST also remove it on all exit paths. The rollback() cleanup was specifically fixed in Release 1; without it, every failed upgrade left a permanent stale flag.

## executeUpgrade pipeline

1. Pre-flight checks: downgrade guard, release-assets manifest, disk space, commit signature.
2. **writeUpgradeFlag** — flag goes on disk; mutex is now held.
3. Maintenance mode on (web UI shows "upgrading").
4. Stop application services; take DB backup.
5. `git checkout` target commit.
6. Docker compose pull new images.
7. Start database; wait for health.
8. `./sb migrate up --verbose` — apply pending migrations.
9. Start application services; wait for health.
10. Post-upgrade install fixup: `runInstallFixup` runs `./sb install --non-interactive --inside-active-upgrade` with `STATBUS_INSIDE_ACTIVE_UPGRADE=1`. The bypass signals are necessary because our flag is still on disk at this point; without them the child install would abort with "upgrade in progress".
11. Self-update binary if newer (`exit 42` → systemd respawn).
12. Mark `completed_at` on the DB row (or inherit the mark from `recoverFromFlag` on exit-42 path).
13. **removeUpgradeFlag** — mutex released.
14. Supersede older available rows; notify UI.

If any step from 4 onward fails, `rollback()` is called. It restores the previous git state, DB backup, and services, then removes the flag.

## Recovery contract (`recoverFromFlag`)

Called once at service startup, before the main loop begins. Three outcomes:

1. **No flag on disk** → Idle; proceed.
2. **Flag on disk, owning PID is alive AND isn't us** → pathological (advisory DB lock should prevent two services coexisting). Log an error and refuse to clean up; leave the flag for the operator to investigate.
3. **Flag on disk, owning PID is dead** → the prior upgrade crashed or was killed. Compare git HEAD to `flag.CommitSHA`:
   - Match → the upgrade reached self-update + exit 42; mark `completed_at`.
   - Mismatch → real failure; mark `error` + `rollback_completed_at`.
   Remove the flag. State is now Idle; main loop proceeds.

This is the ground-truth for "service autocorrects on startup." It is not optional, not a sweep, not belt-and-suspenders — it runs every time the service process starts (including every systemd restart) and must leave the server consistent before the main loop ticks.

## Mutex check in `./sb install`

See `cli/cmd/install.go:checkUpgradeMutex`. Called at the top of `runInstall` before any destructive step.

- If the `--inside-active-upgrade` flag is set OR `STATBUS_INSIDE_ACTIVE_UPGRADE=1` env var is set, the check logs and proceeds. The ONLY legitimate caller that sets these is `runInstallFixup` in the upgrade service. Operators must never pass them.
- If the flag file is present and no bypass is set, the check aborts with a diagnostic message based on `pidAlive(flag.PID)`.

See `install-mutex.md` for the decision-tree and operator-facing messages.

## Related

- `doc/install-mutex.md` — mutex schema, decision tree, operator guidance.
- `doc/install-statbus.md` — where `install.sh` lives (spoiler: sibling repo `statbus-web`) and how it gets deployed.
- `doc/CLOUD.md` — fleet-level deployment flow via GitHub Actions.
- `doc/DEPLOYMENT.md` — single-instance install and service management.
- `doc/upgrades.md` — operator runbook: troubleshooting, log locations, manual triggers.
