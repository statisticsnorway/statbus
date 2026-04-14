# Upgrade System

The canonical reference for how StatBus upgrades itself. Three orchestration paths exist; they must never fight each other. The mutex contract described here is enforced in code so that running a manual install while the service is mid-upgrade fails loud with a diagnostic, rather than corrupting state.

## Three orchestration paths

| Path | Entry point | Owns | Respects | When to use |
|---|---|---|---|---|
| **Service** (automatic) | `./sb upgrade service` running as systemd user unit `statbus-upgrade@<slot>.service` | End-to-end upgrade lifecycle: discover → schedule → execute → recover | Its own advisory lock, the shared O_EXCL mutex flag | Production norm. Discovers and applies releases on a 6-hour cycle or on NOTIFY. |
| **Manual install** | `./sb install` | Step-by-step repair of a single host (Prerequisites, Repository, Binary, Config, …, Migrations, …, Upgrade service) | The shared O_EXCL mutex flag — atomically acquires before any destructive step, releases via defer | First-time install or when an operator needs to repair a specific host. |
| **Cloud tool** | `./cloud.sh install <server>` | Fleet-level remote install: SSH + stop_and_unwedge + run install + ensure_service_started | Its own fleet semantics; defers to the shared mutex for per-host safety | Operator updating a remote host from their own machine. |

GitHub Actions workflows (`deploy-to-<slot>.yaml`) trigger the service path — they run `./sb upgrade apply-latest` remotely, which sends a NOTIFY that the service picks up. Actions never call `./sb install` directly.

## Flag-file state machine

Both the upgrade service and `./sb install` write `~/statbus/tmp/upgrade-in-progress.json` via `O_CREATE|O_EXCL` — the kernel guarantees exactly one writer wins. The `Holder` field records which actor owns the file. The flag is the single source of truth for "is an orchestrated mutator in flight or crashed pending recovery".

Two formal states:

| State | Flag present | Meaning |
|---|---|---|
| **Idle** | no | Nothing orchestrated. Any caller (service, install, cloud.sh) can acquire. |
| **InProgress** | yes | Either a live mutator (Holder=service or install) is running OR a prior one crashed and needs recovery. |

Inside InProgress, the flag carries a PID and `pidAlive(PID)` acts as a **diagnostic subquery** that selects between two messages:
- PID alive → "wait for the running {upgrade|install}"
- PID dead → "previous {upgrade|install} crashed — run `./sb upgrade recover`"

This is not a third state: it's an explanation for why the same InProgress state blocks the caller.

### Flag schema (`UpgradeFlag` in `cli/internal/upgrade/service.go`)

```go
type UpgradeFlag struct {
    ID          int       `json:"id"`           // public.upgrade.id (0 when Holder=="install")
    CommitSHA   string    `json:"commit_sha"`   // target commit ("" when Holder=="install")
    DisplayName string    `json:"display_name"` // tag, sha-prefix, or install description
    PID         int       `json:"pid"`          // os.Getpid() at write
    StartedAt   time.Time `json:"started_at"`
    InvokedBy   string    `json:"invoked_by"`   // e.g. "scheduled", "operator:jhf"
    Trigger     string    `json:"trigger"`      // coarse bucket for logs
    Holder      string    `json:"holder"`       // "service" or "install"
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

Called once at service startup, before the main loop begins. Also exposed as `./sb upgrade recover` for one-shot reconciliation when the service is stopped (e.g., after `./cloud.sh install` killed the unit mid-upgrade). Outcomes:

1. **No flag on disk** → Idle; proceed.
2. **Flag on disk, owning PID is alive AND isn't us** → pathological (advisory DB lock should prevent two services coexisting; an install holder would be a surprise concurrent operator). Log an error and refuse to clean up; leave the flag for the operator to investigate.
3. **Flag on disk, owning PID is dead, Holder == "install"** → install crashed or was killed. There is no `public.upgrade` row to reconcile (install doesn't write one). Just remove the flag.
4. **Flag on disk, owning PID is dead, Holder == "service"** (or empty for legacy) → service crashed mid-upgrade. Compare git HEAD to `flag.CommitSHA`:
   - Match → the upgrade has landed at the target commit (either via normal completion, or via self-update + exit 42, or any other path that left HEAD on the target SHA); mark `completed_at`. The recovery code keys on `HEAD == flag.CommitSHA` and is intentionally agnostic about how HEAD got there.
   - Mismatch → real failure; mark `error` + `rollback_completed_at`.
   Remove the flag. State is now Idle; main loop proceeds.

This is the ground-truth for "service autocorrects on startup." It is not optional, not a sweep, not belt-and-suspenders — it runs every time the service process starts (including every systemd restart) and must leave the server consistent before the main loop ticks.

## Mutex acquire in `./sb install`

See `cli/cmd/install.go:acquireOrBypass` and `cli/internal/upgrade/service.go:AcquireInstallFlag`. Called at the top of `runInstall` before any destructive step; release is deferred so all exit paths clean up.

- If the `--inside-active-upgrade` flag is set OR `STATBUS_INSIDE_ACTIVE_UPGRADE=1` env var is set, install does NOT acquire (the parent service already holds the flag). The ONLY legitimate caller that sets these is `runInstallFixup` in the upgrade service. Operators must never pass them.
- Otherwise, install attempts an O_EXCL acquire. On success, defer-release on exit. On contention, abort with a diagnostic that branches on `Holder` and `pidAlive(flag.PID)` — see `install-mutex.md` for the message table.

## Related

- `doc/install-mutex.md` — mutex schema, decision tree, operator guidance.
- `doc/install-statbus.md` — where `install.sh` lives (spoiler: sibling repo `statbus-web`) and how it gets deployed.
- `doc/CLOUD.md` — fleet-level deployment flow via GitHub Actions.
- `doc/DEPLOYMENT.md` — single-instance install and service management.
- `doc/upgrades.md` — operator runbook: troubleshooting, log locations, manual triggers.
